#!/usr/bin/env node
// Keeps the number of branches on GitHub under a cap by deleting the oldest
// ones, so merged-and-forgotten feature branches don't pile up forever.
//
// Run by `.github/workflows/prune-old-branches.yml` every time something
// lands on `dev`; also runnable by hand:
//
//   GITHUB_TOKEN=... node tool/ci/prune_old_branches.mjs --dry-run
//   GITHUB_TOKEN=... node tool/ci/prune_old_branches.mjs --limit 8
//
// "Oldest" means the branch whose tip commit is oldest — the branch nobody
// has touched in the longest time, which is what you actually want gone, not
// whichever was created first.
//
// The cap counts *every* branch in the repo, including the protected ones, so
// `--limit 8` with four long-lived branches leaves room for four feature
// branches. Only unprotected branches are ever deleted.
//
// Deleting a branch on GitHub throws away any commit that isn't reachable
// from another ref, so this refuses to touch anything that still looks live:
// the long-lived branches, the repo's default branch, anything GitHub marks
// as protected, and any branch with an open PR. Everything else is fair game
// once the repo is over the cap — including unmerged work, which is the point
// of a cap but also why `--dry-run` exists.
//
// Zero dependencies: plain fetch against the REST API.

const PROTECTED = new Set([
  'dev',
  'staging',
  'main',
  'master',
  // Orphan branch holding the shared test-report store that the app bundles
  // and `tool/sync_test_report.dart` reads. It only moves when CI publishes,
  // so it goes stale quickly and would otherwise be a prime deletion target —
  // losing it breaks Tools -> Test Results. See tool/ci/publish_test_report.sh.
  'ci-reports',
]);

const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
// Opt-in safety net: only ever delete branches whose commits are already on
// `dev`, so a stale-but-unmerged experiment survives the cap. Off by default
// because then a repo full of unmerged branches never gets back under it.
const mergedOnly = args.includes('--merged-only');
const limitArg = args.indexOf('--limit');
const LIMIT = limitArg === -1 ? 8 : Number(args[limitArg + 1]);

if (!Number.isInteger(LIMIT) || LIMIT < 1) {
  console.error(`--limit must be a positive integer, got "${args[limitArg + 1]}"`);
  process.exit(2);
}

const token =
  process.env.GITHUB_TOKEN || process.env.GH_TOKEN || process.env.INPUT_TOKEN;
if (!token) {
  console.error('No GITHUB_TOKEN/GH_TOKEN in the environment.');
  process.exit(2);
}

// GITHUB_REPOSITORY is set by Actions; fall back to the git remote locally.
let repoSlug = process.env.GITHUB_REPOSITORY;
if (!repoSlug) {
  const { execSync } = await import('node:child_process');
  const url = execSync('git remote get-url origin', { encoding: 'utf8' }).trim();
  const match = url.match(/github\.com[:/](.+?)(?:\.git)?$/);
  if (!match) {
    console.error(`Could not work out the repo from remote "${url}".`);
    process.exit(2);
  }
  repoSlug = match[1];
}
const API = `https://api.github.com/repos/${repoSlug}`;

async function api(path, options = {}) {
  const response = await fetch(`${API}${path}`, {
    ...options,
    headers: {
      accept: 'application/vnd.github+json',
      authorization: `Bearer ${token}`,
      'user-agent': 'besttodo-branch-pruner',
      ...(options.headers || {}),
    },
  });
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`${options.method || 'GET'} ${path} -> ${response.status}: ${body}`);
  }
  return response.status === 204 ? null : response.json();
}

async function paged(path) {
  const out = [];
  for (let page = 1; ; page++) {
    const batch = await api(`${path}${path.includes('?') ? '&' : '?'}per_page=100&page=${page}`);
    out.push(...batch);
    if (batch.length < 100) return out;
  }
}

const repo = await api('');
const branches = await paged('/branches');
const openPrs = await paged('/pulls?state=open');
const prBranches = new Set(openPrs.map((pr) => pr.head.ref));

console.log(`${repoSlug}: ${branches.length} branch(es), cap is ${LIMIT}.`);

if (branches.length <= LIMIT) {
  console.log('Under the cap — nothing to delete.');
  process.exit(0);
}

function keepReason(branch) {
  if (PROTECTED.has(branch.name)) return 'long-lived branch';
  if (branch.name === repo.default_branch) return 'default branch';
  if (branch.protected) return 'protected on GitHub';
  if (prBranches.has(branch.name)) return 'has an open PR';
  return null;
}

// The tip commit's date is what orders these, and the branch list doesn't
// carry it, so ask for each one. Committer date, not author date: a rebased
// or cherry-picked branch should count as recently touched.
const dated = [];
for (const branch of branches) {
  const reason = keepReason(branch);
  if (reason) {
    console.log(`  keep   ${branch.name} (${reason})`);
    continue;
  }
  const commit = await api(`/commits/${branch.commit.sha}`);
  dated.push({
    name: branch.name,
    date: new Date(commit.commit.committer.date),
  });
}

dated.sort((a, b) => a.date - b.date);

const overBy = branches.length - LIMIT;

let candidates = dated;
if (mergedOnly) {
  candidates = [];
  for (const branch of dated) {
    // ahead_by counts commits the branch has that `dev` doesn't; zero means
    // everything on it already landed, so deleting it loses nothing.
    const cmp = await api(
      `/compare/${encodeURIComponent('dev')}...${encodeURIComponent(branch.name)}`,
    );
    if (cmp.ahead_by === 0) {
      candidates.push(branch);
    } else {
      console.log(
        `  keep   ${branch.name} (${cmp.ahead_by} commit(s) not on dev, --merged-only)`,
      );
    }
  }
}

const doomed = candidates.slice(0, overBy);

if (doomed.length < overBy) {
  console.log(
    `Over the cap by ${overBy} but only ${doomed.length} branch(es) can be ` +
      'deleted; the rest are protected or have open PRs.',
  );
}

for (const branch of doomed) {
  const stamp = branch.date.toISOString().slice(0, 10);
  if (dryRun) {
    console.log(`  WOULD DELETE ${branch.name} (last commit ${stamp})`);
    continue;
  }
  try {
    await api(`/git/refs/heads/${encodeURIComponent(branch.name)}`, {
      method: 'DELETE',
    });
    console.log(`  deleted ${branch.name} (last commit ${stamp})`);
  } catch (error) {
    // A branch deleted between listing and now isn't a failure.
    if (/-> 4(04|22)/.test(error.message)) {
      console.log(`  ${branch.name} was already gone`);
    } else {
      throw error;
    }
  }
}

const remaining = branches.length - (dryRun ? 0 : doomed.length);
console.log(`Done — ${remaining} branch(es)${dryRun ? ' (dry run, nothing deleted)' : ''}.`);

/// Non-browser stand-ins for the approvals site's browser hooks (tests).

/// Throws away everything the tab holds in memory.
void reloadPage() {}

/// Whether the page runs inside another page's frame.
bool isFramed() => false;

/// Turns the browser's "Leave site? Changes may not be saved" prompt on/off.
void setLeaveWarning(bool on) {}

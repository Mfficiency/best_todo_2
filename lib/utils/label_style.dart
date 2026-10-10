import 'package:flutter/material.dart';

import 'label_utils.dart';

/// One fixed accent for every reserved state tag ([protectedStateTokens]),
/// wherever a label renders as a chip — typing one of these by hand is a
/// naming collision with something the app already gives special meaning
/// (like naming a file with a reserved extension), so it needs to look
/// different from a plain user tag on sight, not just in a tooltip.
const Color protectedTagColor = Color(0xFFE65100); // deep orange 900

/// [protectedTagColor] when [token] is reserved (see [isProtectedToken]),
/// otherwise null — callers fall back to their normal chip styling.
Color? protectedChipColorFor(String token) =>
    isProtectedToken(token) ? protectedTagColor : null;

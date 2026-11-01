#!/usr/bin/env python3
"""Small dependency guard; it supplements review and does not parse Swift semantics."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'AirIsland'
errors = []

# The model and scheduler must remain usable without a window, device or SwiftUI.
for directory, allowed_imports in [('Activities', {'Foundation'}),
                                   ('Scheduling', {'Foundation', 'Combine', 'Defaults'})]:
    for path in (APP / directory).rglob('*.swift'):
        source = path.read_text()
        imports = set(re.findall(r'^import\s+(\w+)', source, re.MULTILINE))
        for module in imports - allowed_imports:
            errors.append(f'{path.relative_to(ROOT)}: disallowed dependency {module}')
        for token in ['MusicManager.shared', 'VolumeManager.shared', 'BrightnessManager.shared',
                      'NSWindow', 'NSWorkspace', 'ContentView(', 'IslandWindowCoordinator.shared']:
            if token in source:
                errors.append(f'{path.relative_to(ROOT)}: reverse dependency {token}')

# Sources submit facts instead of restoring the former parallel presentation channels.
for path in APP.rglob('*.swift'):
    source = path.read_text()
    for token in ['toggleExpandingView(', 'toggleSneakPeek(', 'coordinator.sneakPeek',
                  'coordinator.expandingView']:
        if token in source:
            errors.append(f'{path.relative_to(ROOT)}: legacy scheduling bypass {token}')

if errors:
    raise SystemExit('\n'.join(errors))
print('Activity dependency boundaries passed (static guard; review still required).')

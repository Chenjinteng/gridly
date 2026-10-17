#!/usr/bin/env python3
"""Patch macos/Runner.xcodeproj/project.pbxproj to add a Run Script build phase
that copies build/web/* to the .app's Resources/web/ before bundling.

This solves the macOS sandbox issue: the app can't read
~/Documents/Projects/gridly/build/web/ from inside the sandbox container.
By bundling web into .app/Contents/Resources/web/, the read is internal to
the bundle and works.

P3 commit 14.
"""
import sys

p = 'macos/Runner.xcodeproj/project.pbxproj'
with open(p, 'r') as f:
    s = f.read()

# Unique UUID prefix to avoid clash with Xcode defaults (33CC, 3399, etc.)
NEW_PHASE_ID = 'AABB11223344C6BF0003C999'

# 1. Insert new PBXShellScriptBuildPhase before "/* End PBXShellScriptBuildPhase section */"
new_phase_block = (
    f'\t\t{NEW_PHASE_ID} /* Bundle Web Assets */ = {{\n'
    f'\t\t\tisa = PBXShellScriptBuildPhase;\n'
    f'\t\t\talwaysOutOfDate = 1;\n'
    f'\t\t\tbuildActionMask = 2147483647;\n'
    f'\t\t\tfiles = (\n'
    f'\t\t\t);\n'
    f'\t\t\tinputFileListPaths = (\n'
    f'\t\t\t);\n'
    f'\t\t\tinputPaths = (\n'
    f'\t\t\t\t"$(SRCROOT)/../build/web/",\n'
    f'\t\t\t);\n'
    f'\t\t\toutputFileListPaths = (\n'
    f'\t\t\t);\n'
    f'\t\t\toutputPaths = (\n'
    f'\t\t\t\t"$(BUILT_PRODUCTS_DIR)/$(WRAPPER_NAME)/Contents/Resources/web/",\n'
    f'\t\t\t);\n'
    f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
    f'\t\t\tshellPath = /bin/sh;\n'
    f'\t\t\tshellScript = "set -e\\n'
    f'# LAN_WEB P3 commit 14: copy Flutter web build into .app bundle\\n'
    f'# Resolves macOS sandbox: app cannot read project build/web/ from sandbox.\\n'
    f'# Bundle into .app/Contents/Resources/web/ and server reads from Platform.script.parent + ../../../Resources/web/\\n'
    f'# Run ./scripts/build_web_for_macos.sh first to build the web.\\n'
    f'if [ -d \\"$SRCROOT/../build/web\\" ]; then\\n'
    f'\\techo \\"[lan_web/bundle] copying build/web/ -> .app/Resources/web/\\"\\n'
    f'\\tmkdir -p \\"$BUILT_PRODUCTS_DIR/$WRAPPER_NAME/Contents/Resources/web\\"\\n'
    f'\\trm -rf \\"$BUILT_PRODUCTS_DIR/$WRAPPER_NAME/Contents/Resources/web\\"/*\\n'
    f'\\tcp -R \\"$SRCROOT/../build/web/\\"* \\"$BUILT_PRODUCTS_DIR/$WRAPPER_NAME/Contents/Resources/web/"\\n'
    f'\\techo \\"[lan_web/bundle] done\\"\\n'
    f'else\\n'
    f'\\techo \\"[lan_web/bundle] WARN: build/web/ not found. Run ./scripts/build_web_for_macos.sh to build web.\\"\\n'
    f'fi\\n'
    f'";\n'
    f'\t}};\n'
)

marker = '/* End PBXShellScriptBuildPhase section */'
if marker not in s:
    print('ERROR: PBXShellScriptBuildPhase end marker not found', file=sys.stderr)
    sys.exit(1)

s = s.replace(marker, new_phase_block + '\n' + marker, 1)

# 2. Add the new phase ID to the Runner target's buildPhases list
runner_start = s.find('33CC10EC2044A3C60003C045 /* Runner */ = {')
if runner_start == -1:
    print('ERROR: Runner target not found', file=sys.stderr)
    sys.exit(1)
phases_start = s.find('buildPhases = (', runner_start)
phases_end = s.find(');', phases_start) + 2
phases_block = s[phases_start:phases_end]
# Skip if already added (idempotent)
if NEW_PHASE_ID in phases_block:
    print('Already added, skipping')
else:
    new_phases = phases_block + f'\n\t\t\t\t{NEW_PHASE_ID} /* Bundle Web Assets */,'
    s = s[:phases_start] + new_phases + s[phases_end:]

with open(p, 'w') as f:
    f.write(s)
print('OK')

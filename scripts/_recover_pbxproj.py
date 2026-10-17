#!/usr/bin/env python3
"""Recover macos/Runner.xcodeproj/project.pbxproj from Flutter template.

Context: P3 commit 14 (`91dde68`) corrupted pbxproj to 0 bytes via broken shell
escape. This script rebuilds pbxproj from Flutter template with proper Mustache
substitutions:

  - {{macosIdentifier}}                  -> cn.jinteng.gridly
  - {{projectName}}                      -> gridly
  - {{#withSwiftPackageManager}} ... {{/withSwiftPackageManager}}
        Modern Flutter (3.16+) enables SPM by default. KEEP content, REMOVE markers.
  - {{#withPlatformChannelPluginHook}} ... {{/withPlatformChannelPluginHook}}
        SPM is enabled, so CocoaPods plugin hook is NOT used. REMOVE block entirely.
  - {{pluginProjectName}}                -> n/a (only inside withPlatformChannelPluginHook)

After substitution, also adds the "Bundle Web Assets" PBXShellScriptBuildPhase that
copies build/web/* into .app/Contents/Resources/web/ at build time.
"""
import sys

TEMPLATE = '/usr/local/share/flutter/packages/flutter_tools/templates/app/macos.tmpl/Runner.xcodeproj/project.pbxproj.tmpl'
TARGET = 'macos/Runner.xcodeproj/project.pbxproj'

MACOS_IDENTIFIER = 'cn.jinteng.gridly'
PROJECT_NAME = 'gridly'

PHASE_ID = 'AABB11223344C6BF0003C999'


def read_template():
    with open(TEMPLATE, 'r') as f:
        return f.read()


def substitute(s):
    # 1. Remove {{#withPlatformChannelPluginHook}}...{{/withPlatformChannelPluginHook}} blocks entirely
    #    (these are inside {{#withSwiftPackageManager}} which is true, so the inner is processed first)
    import re
    # Multiline non-greedy: match the marker line + everything until the closing marker line
    pat_inner = re.compile(
        r'^[ \t]*\{\{#withPlatformChannelPluginHook\}\}\n.*?^[ \t]*\{\{/withPlatformChannelPluginHook\}\}\n',
        re.MULTILINE | re.DOTALL,
    )
    s = pat_inner.sub('', s)

    # 2. Strip Mustache section markers, INCLUDING leading whitespace + trailing newline,
    #    so the entire marker line disappears (not just the marker text — otherwise the
    #    residual '\t\t\n' merges with the next line's '\t\t...' and produces 4-tab indent).
    s = re.sub(r'^[ \t]*\{\{#withSwiftPackageManager\}\}\n', '', s, flags=re.MULTILINE)
    s = re.sub(r'^[ \t]*\{\{/withSwiftPackageManager\}\}\n', '', s, flags=re.MULTILINE)

    # 3. Replace remaining {{...}} variables
    s = s.replace('{{macosIdentifier}}', MACOS_IDENTIFIER)
    s = s.replace('{{projectName}}', PROJECT_NAME)
    # {{pluginProjectName}} should be gone after step 1, but as a safety net:
    s = s.replace('{{pluginProjectName}}', 'PLACEHOLDER')

    return s


def add_bundle_phase(s):
    if PHASE_ID in s:
        return s  # idempotent

    # IMPORTANT: Use single quotes inside the shell script, NEVER double quotes.
    # IMPORTANT: pbxproj shellScript MUST use escaped double quotes (\\")
    # around $VAR references, NOT single quotes. Single quotes prevent shell
    # variable expansion, so $SRCROOT stays literal text and the script always
    # sees "WARN: build/web/ not found". See pbxproj line 321/341 (Flutter's
    # own scripts use \\"$FLUTTER_ROOT\\" pattern) for the canonical fix.
    shell_script = (
        'set -e; '
        'if [ -d \\"$SRCROOT/../build/web\\" ]; then '
        'echo \\"[lan_web/bundle] copying build/web/ -> .app/Resources/web/\\"; '
        'mkdir -p \\"$BUILT_PRODUCTS_DIR/$WRAPPER_NAME/Contents/Resources/web\\"; '
        'rm -rf \\"$BUILT_PRODUCTS_DIR/$WRAPPER_NAME/Contents/Resources/web\\"/*; '
        'cp -R \\"$SRCROOT/../build/web/\\"* \\"$BUILT_PRODUCTS_DIR/$WRAPPER_NAME/Contents/Resources/web/\\"; '
        'echo \\"[lan_web/bundle] done\\"; '
        'else '
        'echo \\"[lan_web/bundle] WARN: build/web/ not found. Run ./scripts/build_web_for_macos.sh to build web.\\"; '
        'fi'
    )

    new_phase_block = (
        f'\t\t{PHASE_ID} /* Bundle Web Assets */ = {{\n'
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
        f'\t\t\tshellScript = "{shell_script}";\n'
        f'\t}};\n'
    )

    marker = '/* End PBXShellScriptBuildPhase section */'
    if marker not in s:
        print('ERROR: PBXShellScriptBuildPhase end marker not found', file=sys.stderr)
        sys.exit(1)
    s = s.replace(marker, new_phase_block + '\n' + marker, 1)

    # Add the new phase ID to the main Runner target's buildPhases list.
    # IMPORTANT: there are TWO "Runner"-prefixed targets in the file:
    #   1. RunnerTests  (PBXNativeTarget, earlier in the file, test target)
    #   2. Runner       (PBXNativeTarget, main app target — the one we want)
    # Naive "s.find('Runner */ = {')" matches RunnerTests first and adds the
    # build phase to the wrong target. We must skip RunnerTests and find the
    # SECOND occurrence.
    runner_start = -1
    search_from = 0
    while True:
        idx = s.find('33CC10EC2044A3C60003C045 /* Runner */ = {', search_from)
        if idx == -1:
            break
        runner_start = idx
        search_from = idx + 1
    if runner_start == -1:
        print('ERROR: Main Runner target (33CC10EC2044A3C60003C045) not found', file=sys.stderr)
        sys.exit(1)
    phases_start = s.find('buildPhases = (', runner_start)
    if phases_start == -1:
        print('ERROR: buildPhases not found in Runner target', file=sys.stderr)
        sys.exit(1)
    # Find the closing ');' — the new phase ref must be inserted BEFORE it
    # (inside the parens), not after. Inserting after breaks Xcode parsing.
    phases_close = s.find(');', phases_start)
    # Insert at the newline right before ');' (the last entry in buildPhases
    # ends with a trailing newline), so the new phase goes on its own line.
    insert_at = s.rfind('\n', phases_start, phases_close) + 1
    new_phases = f'\t\t\t\t{PHASE_ID} /* Bundle Web Assets */,\n'
    s = s[:insert_at] + new_phases + s[insert_at:]

    return s


def main():
    raw = read_template()
    sub = substitute(raw)
    final = add_bundle_phase(sub)
    with open(TARGET, 'w') as f:
        f.write(final)
    print(f'Wrote {TARGET} ({len(final)} chars)')


if __name__ == '__main__':
    main()
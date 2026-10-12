# flutter run, with a quiet terminal.
#
#   .\tool\run.ps1                 run on the connected phone
#   .\tool\run.ps1 -d <device-id>  pick a device
#   .\tool\run.ps1 --release       any other flutter run flag works too
#
# Shows only:
#   [net]  downloads / requests      [nav]  page + tab changes
#   [db]   database reads + writes   [err]  uncaught errors
# plus flutter's own build / hot-reload messages. Everything else the phone's OS prints
# (avc denials, binder, Choreographer, vendor services, plugin chatter) is dropped here.
# Hot reload still works: press r, R, q in this terminal as usual.

$keep = @(
    '\[(net|nav|db|err|ai)\]',                                   # the app's own lines
    '^(Launching|Running Gradle|Running Xcode|Installing|Syncing files|Waiting for|Performing hot|Reloaded|Restarted|Hot reload|Hot restart)',
    '^(Built |Flutter run key commands|A Dart VM|The Flutter DevTools|An Observatory|Application finished|Lost connection)',
    '^\s*(r|R|h|d|c|q|p|P|o|s) +(Hot|List|Detach|Clear|Quit|Toggle|Dump|Take)',
    'EXCEPTION CAUGHT|Unhandled Exception|FAILURE:|BUILD FAILED|What went wrong|error:|Error:|Gradle task .* failed',
    '^Reloaded|^Restarted'
)
$pattern = ($keep -join '|')

& flutter run @args 2>&1 | ForEach-Object {
    $line = "$_"
    # "I/flutter ( 5006): [db] ..." -> "[db] ..."
    $line = $line -replace '^[A-Z]/flutter\s*\(\s*\d+\):\s?', ''
    if ($line -match $pattern) { $line }
}

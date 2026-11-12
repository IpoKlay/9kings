"""Check engine stderr after shutdown, since Godot can report leaks with exit code 0."""
import argparse
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--audio-driver', default='Dummy')
    parser.add_argument('--display', action='store_true')
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    output = project.parent / 'output' / 'audio-shutdown'
    output.mkdir(parents=True, exist_ok=True)
    command = [args.godot, '--verbose', '--audio-driver', args.audio_driver,
               '--path', str(project)]
    if not args.display:
        command.append('--headless')
    for mode in ['release', 'menu-close', 'battle-close']:
        result = subprocess.run(command + ['--script', 'res://tests/test_audio_shutdown.gd',
                                          '--', mode], capture_output=True, text=True, timeout=60)
        log = result.stdout + result.stderr
        (output / (mode + '.log')).write_text(log)
        marker = 'AUDIO SHUTDOWN CHECKS=18 FAILURES=0' if mode == 'release' else 'WINDOW CLOSE DURING AUDIO: ' + mode
        errors = [line for line in log.splitlines()
                  if any(tag in line for tag in ['ERROR:', 'WARNING:', 'Leaked instance:', 'Resource still in use:'])]
        if result.returncode != 0 or marker not in log or errors:
            raise SystemExit(f'{mode} failed (exit {result.returncode}):\n{log}')
        print(f'{mode}: passed, no shutdown warnings', flush=True)


if __name__ == '__main__':
    main()

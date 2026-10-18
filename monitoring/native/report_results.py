"""Emit bounded text to normal Actions logs/summary; never upload artifacts or images."""
import os
from pathlib import Path

TEXT_LIMIT = 32768


def read_bounded(path):
    with path.open('r', errors='replace') as stream:
        value = stream.read(TEXT_LIMIT + 1)
    return value[:TEXT_LIMIT] + ('\n[truncated; full test output is in workflow logs]' if len(value) > TEXT_LIMIT else '')


def render(root):
    blocks = ['# Native simulator observation',
        'Fixture regressions, live navigation and live API observations are separate. '
        'No continuous uptime or prediction accuracy claim.',
        '**Logs-only retention. Screenshots are transient on the runner and unavailable after the job. '
        'No artifacts, caches, ZIP files or screenshot data are uploaded.**']
    for name in ('source-sha.txt', 'monitor-sha.txt', 'toolchain.txt', 'simulator-id.txt',
                 'build-execution.json', 'fixtures-execution.json', 'fixtures-summary.json',
                 'live-ui-execution.json', 'live-ui-summary.json', 'live-api.json',
                 'fixtures-export-errors.log', 'live-ui-export-errors.log'):
        path = root / name
        value = read_bounded(path) if path.exists() else 'unverified / no completion record'
        blocks.append(f'## {name}\n\n````text\n{value}\n````')
    measurements = []
    log = root / 'fixtures.log'
    if log.exists():
        with log.open(errors='replace') as stream:
            for line in stream:
                if 'PIVOT_PERF ' in line or 'PIVOT_PARK_SWITCH ' in line:
                    measurements.append(line[:TEXT_LIMIT])
                    if len(measurements) >= 10:
                        break
    if measurements:
        blocks.append('## Fixture measurements\n\n````text\n' + ''.join(measurements) + '\n````')
    return '\n\n'.join(blocks) + '\n'


def main():
    text = render(Path('build/monitor'))
    print(text)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as stream:
            stream.write(text)


if __name__ == '__main__':
    main()

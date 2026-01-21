#!/usr/bin/env python3
"""
visualize_pipeline.py - CUDA Execution Pipeline Visualizer

Takes CUDA trace data and generates visual pipeline diagrams showing
the complete flow from start to finish with timing information.

Usage:
    python visualize_pipeline.py cuda_trace.jsonl
    python visualize_pipeline.py --format=html cuda_trace.jsonl
    python visualize_pipeline.py --flamegraph cuda_trace.jsonl
"""

import json
import sys
import argparse
from collections import defaultdict
from typing import List, Dict, Tuple
import re

class CUDATraceEvent:
    def __init__(self, ts, name, phase, op_id=None, tid=None, depth=0, details=None):
        self.ts = float(ts)
        self.name = name
        self.phase = phase  # 'B' = begin, 'E' = end
        self.op_id = op_id
        self.tid = tid
        self.depth = int(depth)
        self.details = details or {}

    def __repr__(self):
        return f"<Event {self.name} @ {self.ts:.6f}s depth={self.depth}>"


class PipelineAnalyzer:
    def __init__(self):
        self.events = []
        self.categories = defaultdict(list)
        self.timeline = []

    def load_jsonl(self, filename):
        """Load trace from JSON Lines format"""
        with open(filename, 'r') as f:
            for line in f:
                if not line.strip():
                    continue
                try:
                    data = json.loads(line)
                    event = CUDATraceEvent(
                        ts=data.get('ts', 0),
                        name=data.get('name', 'unknown'),
                        phase=data.get('phase', 'B'),
                        op_id=data.get('op_id'),
                        tid=data.get('tid'),
                        depth=data.get('depth', 0),
                        details=data.get('details', {})
                    )
                    self.events.append(event)
                except json.JSONDecodeError as e:
                    print(f"Warning: Failed to parse line: {e}", file=sys.stderr)

    def match_events(self):
        """Match begin/end events to create complete operations"""
        stack = {}  # op_id -> begin_event

        for event in sorted(self.events, key=lambda e: e.ts):
            if event.phase == 'B':
                stack[event.op_id] = event
            elif event.phase == 'E' and event.op_id in stack:
                begin = stack.pop(event.op_id)
                duration = event.ts - begin.ts

                op = {
                    'name': event.name,
                    'start': begin.ts,
                    'end': event.ts,
                    'duration': duration,
                    'depth': begin.depth,
                    'details': event.details
                }
                self.timeline.append(op)

                # Categorize
                category = self.categorize(event.name)
                self.categories[category].append(op)

    def categorize(self, func_name):
        """Categorize function by name"""
        if 'MemAlloc' in func_name or 'MemFree' in func_name:
            return 'memory_mgmt'
        elif 'Memcpy' in func_name:
            return 'transfer'
        elif 'Launch' in func_name:
            return 'kernel'
        elif 'Ctx' in func_name:
            return 'context'
        elif 'Stream' in func_name:
            return 'stream'
        elif 'Module' in func_name:
            return 'module'
        elif 'Init' in func_name or 'Device' in func_name:
            return 'init'
        elif 'Synchronize' in func_name:
            return 'sync'
        else:
            return 'other'

    def print_ascii_timeline(self):
        """Print ASCII art timeline of execution"""
        if not self.timeline:
            print("No timeline data available")
            return

        print("\n" + "="*100)
        print("CUDA EXECUTION PIPELINE - ASCII Timeline")
        print("="*100 + "\n")

        # Sort by start time
        ops = sorted(self.timeline, key=lambda x: x['start'])

        if not ops:
            print("No operations recorded")
            return

        # Normalize to start at 0
        start_time = ops[0]['start']
        end_time = ops[-1]['end']
        total_duration = end_time - start_time

        print(f"Total execution time: {total_duration*1000:.3f} ms\n")

        # Define categories and their symbols
        category_symbols = {
            'init': '▓',
            'memory_mgmt': '█',
            'transfer': '▒',
            'kernel': '●',
            'sync': '░',
            'context': '◆',
            'stream': '◇',
            'module': '▪',
            'other': '·'
        }

        # Print legend
        print("Legend:")
        for cat, sym in category_symbols.items():
            print(f"  {sym} = {cat}")
        print()

        # Group operations by depth for better visualization
        depth_groups = defaultdict(list)
        for op in ops:
            depth_groups[op['depth']].append(op)

        max_depth = max(depth_groups.keys()) if depth_groups else 0

        # Print timeline for each depth
        timeline_width = 80
        time_markers = 10

        for depth in range(max_depth + 1):
            if depth not in depth_groups:
                continue

            print(f"\nDepth {depth}:")
            print("  ", end="")

            # Create timeline string
            timeline = [' '] * timeline_width

            for op in depth_groups[depth]:
                # Calculate position
                start_pos = int(((op['start'] - start_time) / total_duration) * timeline_width)
                end_pos = int(((op['end'] - start_time) / total_duration) * timeline_width)

                # Ensure at least 1 char wide
                if start_pos == end_pos:
                    end_pos = start_pos + 1

                # Get symbol for category
                category = self.categorize(op['name'])
                symbol = category_symbols.get(category, '·')

                # Fill timeline
                for i in range(start_pos, min(end_pos, timeline_width)):
                    if i < len(timeline):
                        timeline[i] = symbol

            print(''.join(timeline))

        # Print time scale
        print("\n  Time scale (ms):")
        print("  ", end="")
        for i in range(time_markers + 1):
            time_ms = (total_duration * i / time_markers) * 1000
            print(f"{time_ms:>7.1f}", end="")
        print()

    def print_pipeline_summary(self):
        """Print detailed pipeline summary"""
        print("\n" + "="*100)
        print("PIPELINE SUMMARY - Operation Breakdown")
        print("="*100 + "\n")

        # Category totals
        category_stats = {}
        for category, ops in self.categories.items():
            total_time = sum(op['duration'] for op in ops)
            count = len(ops)
            avg_time = total_time / count if count > 0 else 0

            category_stats[category] = {
                'count': count,
                'total_time': total_time,
                'avg_time': avg_time
            }

        # Print category summary
        total_time = sum(stats['total_time'] for stats in category_stats.values())

        print(f"{'Category':<20} {'Count':>10} {'Total Time':>15} {'Avg Time':>15} {'% of Total':>12}")
        print("-" * 100)

        for category in sorted(category_stats.keys()):
            stats = category_stats[category]
            percentage = (stats['total_time'] / total_time * 100) if total_time > 0 else 0

            print(f"{category:<20} {stats['count']:>10} "
                  f"{stats['total_time']*1000:>12.3f} ms "
                  f"{stats['avg_time']*1000:>12.3f} ms "
                  f"{percentage:>11.1f}%")

        print("-" * 100)
        print(f"{'TOTAL':<20} {sum(s['count'] for s in category_stats.values()):>10} "
              f"{total_time*1000:>12.3f} ms")

    def print_detailed_operations(self, limit=20):
        """Print detailed list of longest operations"""
        print("\n" + "="*100)
        print(f"TOP {limit} LONGEST OPERATIONS")
        print("="*100 + "\n")

        # Sort by duration
        longest_ops = sorted(self.timeline, key=lambda x: x['duration'], reverse=True)[:limit]

        print(f"{'#':<4} {'Function':<40} {'Duration':>15} {'Category':<15}")
        print("-" * 100)

        for i, op in enumerate(longest_ops, 1):
            category = self.categorize(op['name'])
            print(f"{i:<4} {op['name']:<40} {op['duration']*1000:>12.3f} ms {category:<15}")

    def generate_flamegraph_data(self, output_file='flamegraph.txt'):
        """Generate data for flamegraph visualization"""
        with open(output_file, 'w') as f:
            for op in sorted(self.timeline, key=lambda x: x['start']):
                # Flamegraph format: stack_trace count
                stack = f"CUDA;{op['name']}"
                count = int(op['duration'] * 1000000)  # Convert to microseconds
                f.write(f"{stack} {count}\n")

        print(f"\nFlamegraph data written to: {output_file}")
        print(f"Generate SVG with: flamegraph.pl {output_file} > flamegraph.svg")

    def generate_chrome_trace(self, output_file='trace.json'):
        """Generate Chrome Trace Event Format (viewable in chrome://tracing)"""
        trace_events = []

        for op in self.timeline:
            # Begin event
            trace_events.append({
                'name': op['name'],
                'cat': self.categorize(op['name']),
                'ph': 'B',  # Begin
                'ts': op['start'] * 1000000,  # Microseconds
                'pid': 1,
                'tid': 1
            })

            # End event
            trace_events.append({
                'name': op['name'],
                'cat': self.categorize(op['name']),
                'ph': 'E',  # End
                'ts': op['end'] * 1000000,
                'pid': 1,
                'tid': 1
            })

        with open(output_file, 'w') as f:
            json.dump({'traceEvents': trace_events}, f, indent=2)

        print(f"\nChrome trace written to: {output_file}")
        print(f"Open in Chrome: chrome://tracing")


def main():
    parser = argparse.ArgumentParser(description='Visualize CUDA execution pipeline')
    parser.add_argument('tracefile', help='Input trace file (JSONL format)')
    parser.add_argument('--format', choices=['ascii', 'chrome', 'flamegraph', 'all'],
                        default='ascii', help='Output format')
    parser.add_argument('--top', type=int, default=20,
                        help='Number of top operations to show')

    args = parser.parse_args()

    analyzer = PipelineAnalyzer()

    print(f"Loading trace from: {args.tracefile}")
    analyzer.load_jsonl(args.tracefile)

    print(f"Loaded {len(analyzer.events)} events")

    analyzer.match_events()
    print(f"Matched {len(analyzer.timeline)} operations\n")

    if args.format in ['ascii', 'all']:
        analyzer.print_ascii_timeline()
        analyzer.print_pipeline_summary()
        analyzer.print_detailed_operations(args.top)

    if args.format in ['chrome', 'all']:
        analyzer.generate_chrome_trace()

    if args.format in ['flamegraph', 'all']:
        analyzer.generate_flamegraph_data()


if __name__ == '__main__':
    main()

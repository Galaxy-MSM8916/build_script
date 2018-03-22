#!/usr/bin/env python3

import argparse

def parse_args():
    parser = argparse.ArgumentParser(description='Build script.')

    parser.add_argument('-t', '--target', metavar='target', type=str, required=True, nargs=1, help='Build target.', choices=get_targets())

    parser.add_argument('-d', '--device', metavar='device', type=str, nargs=1, help='Device codename.', choices=get_devices())

    args = parser.parse_args()

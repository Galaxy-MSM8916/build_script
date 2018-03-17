#!/usr/bin/env python3

import getopt
import os
import sys

import conf

file_name = os.path.basename(sys.argv[0])

def usage():
    print("Usage: {} -t <target> [OPTIONS]".format(file_name))

if __name__ == "__main__":
    usage()

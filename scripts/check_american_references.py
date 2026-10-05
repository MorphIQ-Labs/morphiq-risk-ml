#!/usr/bin/env python3
"""Verify source-bound American fixtures offline; no pricing accuracy inference."""
import argparse
from american_reference_data import verify_manifest


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='american-reference-check 1')
    p.add_argument('arguments',nargs='*',help=argparse.SUPPRESS)
    if p.parse_args().arguments: p.error('no positional arguments accepted')
    print(f'American reference provenance/schema: {verify_manifest()} cases verified')


if __name__=='__main__': main()

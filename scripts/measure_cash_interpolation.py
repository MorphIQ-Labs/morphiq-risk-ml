#!/usr/bin/env python3
"""Frozen paired allocation campaign for enclosed cash interpolation."""
from measure_exponential_scratch import main
TARGETS={'cash':.90,'bermudan':.95,'piecewise-cash':.95}
if __name__=='__main__':
    main(description=__doc__,version='cash-interpolation-campaign 1',allocation_targets=TARGETS)

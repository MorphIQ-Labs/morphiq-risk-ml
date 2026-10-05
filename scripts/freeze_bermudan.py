#!/usr/bin/env python3
"""Freeze original binary64 Bermudan schedules before numerical execution."""
import argparse, json, struct
from pathlib import Path

def word(x): return struct.pack('>d',float(x)).hex()

def corpus():
    rows=[]
    def add(name,side='put',dates=(.5,1.),cash=(),valuation=0,**changes):
        p=dict(spot=100.,strike=100.,rate=.05,yield_=.02,volatility=.2,time=1.)
        p.update(changes)
        rights=[(x,0) if not isinstance(x,tuple) else x for x in dates]
        p['opens']=rights[0][0]
        rows.append(dict(id=name,side=side,inputs={k:word(v) for k,v in p.items()},
            valuation_side=valuation,opening_side=rights[0][1],expiry_side=rights[-1][1],
            cash=[dict(time=word(t),amount=word(a)) for t,a in cash],
            exercise=[dict(time=word(t),side=s) for t,s in rights],
            epsilon=word(2**-16*max(p['spot'],p['strike']))))
    add('terminal-call','call',dates=(1.,))
    add('terminal-put',dates=(1.,))
    add('expiry-call','call',dates=(0.,),time=0.,spot=105.)
    add('deterministic-sparse','call',dates=(0.,8.),time=8.,strike=90.,rate=.25,yield_=.125,volatility=0.)
    add('deterministic-middle','call',dates=(0.,4.,8.),time=8.,strike=90.,rate=.25,yield_=.125,volatility=0.)
    add('absorbing-negative-rate',dates=(.5,2.),time=2.,spot=0.,rate=-.125)
    add('zero-strike-negative-yield','call',dates=(.25,1.),strike=0.,yield_=-.125)
    add('deterministic-after','call',dates=((.5,2),1.),cash=((.5,20.),),strike=90.,rate=0.,yield_=0.,volatility=0.)
    add('deterministic-both','call',dates=((.5,1),(.5,2),1.),cash=((.5,20.),),strike=90.,rate=0.,yield_=0.,volatility=0.)
    add('deterministic-large',dates=((.5,2),1.),cash=((.5,5.),),spot=3.,strike=2.,rate=0.,yield_=0.,volatility=0.)
    add('deterministic-joint',dates=((.5,2),1.),cash=((.5,1.),(.5,4.)),spot=3.,strike=2.,rate=0.,yield_=0.,volatility=0.)
    add('zero-time-before-after',dates=((0.,2),),cash=((0.,20.),),valuation=1,time=0.,strike=110.,rate=0.,yield_=0.)
    add('zero-time-after',dates=((0.,2),),cash=((0.,20.),),valuation=2,time=0.,spot=80.,strike=110.,rate=0.,yield_=0.)
    add('terminal-cash-before',dates=((.5,1),),cash=((.5,20.),),time=.5,strike=110.)
    add('terminal-cash-after',dates=((.5,2),),cash=((.5,20.),),time=.5,strike=110.)
    add('put-sparse')
    add('put-irregular',dates=(.125,.375,.875,1.))
    add('put-dense',dates=tuple(i/8 for i in range(1,9)))
    add('put-now',dates=(0.,.5,1.),spot=50.)
    add('put-future',spot=50.)
    add('call-cash-before','call',dates=((.5,1),1.),cash=((.5,5.),))
    add('call-cash-after','call',dates=((.5,2),1.),cash=((.5,5.),))
    add('call-cash-both','call',dates=((.5,1),(.5,2),1.),cash=((.5,5.),))
    add('put-cash-both',dates=((.5,1),(.5,2),1.),cash=((.5,5.),))
    add('put-cash-joint',dates=((.5,1),(.5,2),1.),cash=((.5,3.),(.5,2.)))
    add('put-zero-cash',dates=((.5,1),(.5,2),1.),cash=((.5,0.),))
    add('put-negative-rate',dates=(.25,.75,1.),rate=-.03)
    add('call-negative-rate','call',rate=-.05,yield_=-.02)
    add('put-low-vol',dates=(.5,.75,1.),volatility=.05)
    add('put-short',dates=(1/128,5/256,1/32),time=1/32)
    add('put-liquidator',dates=((.5,1),(.5,2),1.),cash=((.5,5.),),spot=3.,strike=2.)
    add('cash-negative-rate',dates=((.25,1),(.25,2),.75,1.),cash=((.25,5.),),rate=-.03)
    return dict(schema=1,model='constant BSM; finite explicit rights; joint liquidator cash',rows=rows)

if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--version',action='version',version='bermudan-corpus 1');ap.add_argument('--output',type=Path,default=Path('docs/evidence/bermudan/cases-v1.json'));a=ap.parse_args();a.output.write_text(json.dumps(corpus(),indent=2)+'\n')

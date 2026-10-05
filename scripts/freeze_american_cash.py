#!/usr/bin/env python3
"""Original-input cash-event corpus; freeze before pricing comparisons."""
import json
import struct

def word(x): return struct.pack('>d', float(x)).hex()

def corpus():
    rows = []
    def add(name, side='call', s=100., k=100., r=.05, q=.02, vol=.2, t=1., opens=0.,
            cash=((.5,5.),), valuation=0, opening=0, expiry=0):
        rows.append(dict(id=name, side=side,
          inputs={key:word(value) for key,value in zip(
              ('spot','strike','rate','yield_','volatility','time','opens'),(s,k,r,q,vol,t,opens))},
          cash=[dict(time=word(time),amount=word(amount)) for time,amount in cash],
          valuation_side=valuation, opening_side=opening, expiry_side=expiry,
          epsilon=word(max(s,k)/65536)))
    for side in ('call','put'):
        add(side+'-single',side)
        add(side+'-multiple',side,cash=((.25,3.),(.75,4.)))
        add(side+'-large',side,s=20.,k=25.,cash=((.5,40.),))
        add(side+'-zero-dividend',side,cash=((.5,0.),))
        add(side+'-negative-rates',side,r=-.01,q=-.02)
        add(side+'-coincident',side,cash=((.5,5.),(.5,7.)))
        add(side+'-delayed-after',side,opens=.5,opening=2)
        add(side+'-expiry-before',side,cash=((1.,10.),),expiry=1,opens=1.,opening=1)
        add(side+'-expiry-after',side,cash=((1.,10.),),expiry=2,opens=1.,opening=2)
    add('valuation-before',s=105.,cash=((0.,5.),),valuation=1,opening=2,q=0.)
    add('valuation-after',s=100.,cash=((0.,5.),),valuation=2,opening=2,q=0.)
    for side in ('call','put'):
        add(side+'-zero-time-both',side,s=105.,r=0.,q=0.,t=0.,cash=((0.,10.),),valuation=1,opening=1,expiry=2)
        add(side+'-zero-time-after-only',side,s=105.,r=0.,q=0.,t=0.,cash=((0.,10.),),valuation=1,opening=2,expiry=2)
    add('deterministic-joint',side='put',s=10.,k=10.,r=0.,q=0.,vol=0.,cash=((.5,7.),(.5,8.)))
    add('deterministic-interior',s=100.,k=90.,r=.25,q=.125,vol=0.,t=8.,cash=((4.,5.),))
    add('deterministic-rounded-sum',side='put',s=1.,k=1.,r=0.,q=0.,vol=0.,cash=((.5,.1),(.5,.2)))
    add('zero-stock-negative-rate',side='put',s=0.,r=-.125,t=2.)
    add('zero-strike-put',side='put',k=0.)
    add('unrepresentable-joint',side='put',s=10.,k=10.,r=0.,q=0.,vol=0.,cash=((.5,float.fromhex('0x1.fffffffffffffp+1023')),(.5,float.fromhex('0x1.fffffffffffffp+1023'))))
    return dict(schema='american-cash-corpus-v1', sides={'Regular':0,'Before_cash':1,'After_cash':2}, rows=rows)

if __name__ == '__main__':
    print(json.dumps(corpus(),indent=2))

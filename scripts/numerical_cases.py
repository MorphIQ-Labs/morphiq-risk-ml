"""Versioned pre-scoring exact-word membership for numerical campaign v1."""
import hashlib
import math
import random
import struct

VERSION = 1
SEED = 540055
MODELS = ('bsm', 'black76', 'displaced', 'bachelier')
GREEKS = ('delta', 'gamma', 'theta', 'vega', 'rho', 'vanna', 'volga', 'charm', 'veta', 'color')
FIELDS = ('s', 'k', 't', 'r', 'q', 'sigma', 'shift', 'quote', 'limit')
MAX_ROWS = 50000


def bits(x): return struct.pack('>d', x).hex()
def word(x): return struct.unpack('>d', bytes.fromhex(x))[0]
def neighbours(x): return (math.nextafter(x, -math.inf), x, math.nextafter(x, math.inf))


def cases(lane):
    if lane not in ('smoke', 'full'): raise ValueError('unknown campaign lane')
    rows = []
    def add(region, model, values, quantities=('price',), sides=('call', 'put'), modes=('fast', 'production')):
        data = dict(s=1., k=1., t=1., r=0., q=0., sigma=.25, shift=0., quote=0., limit=float.fromhex('0x1.fffffffffffffp+1023'))
        data.update(values)
        for side in sides:
            for quantity in quantities:
                for mode in modes:
                    row = dict(region=region, model=model, side=side, quantity=quantity, mode=mode,
                               inputs={name: bits(data[name]) for name in FIELDS})
                    row['id'] = f'n{len(rows):05d}'
                    rows.append(row)
    for model in MODELS:
        for t in (0., math.nextafter(0., math.inf), -math.nextafter(0., math.inf)):
            add('expiry', model, dict(t=t), ('price', 'delta', 'theta', 'rho', 'veta'))
        for sigma in (0., math.nextafter(0., math.inf)):
            add('zero_variance', model, dict(sigma=sigma), ('price', *GREEKS))
        for s in neighbours(1.):
            add('greek_zeros', model, dict(s=s), ('price', *GREEKS))
        for r in neighbours(.5):
            add('time_zero', model, dict(r=r, q=r, sigma=0.), ('theta', 'rho', 'veta'))
        exponents = (-1074, -1022, 0, 500, 1023) if lane == 'smoke' else (-1074,-1073,-1023,-1022,-1000,-600,-500,-1,0,1,500,600,1000,1022,1023)
        for exponent in exponents:
            scale = math.ldexp(1., exponent)
            add('scale', model, dict(s=scale, k=math.nextafter(scale, 0.),
                sigma=math.ldexp(.25, exponent) if model=='bachelier' else .25),
                ('price', 'gamma', 'rho'), sides=('call',))
        for threshold in (-1024., -256., 256., 1024.):
            for r in neighbours(threshold):
                add('exponential_threshold', model, dict(r=r, q=r), ('price', 'rho'), sides=('call',))
        for distance in (math.nextafter(1., math.inf), 2., 40.):
            add('cancellation_tail', model, dict(s=distance, k=1., sigma=1e-4),
                ('price', 'delta', 'gamma', 'theta'), sides=('call',))
        for limit in (0., 2.**-52, -1., math.inf):
            add('accuracy_limit', model, dict(limit=limit), ('price', 'vega'), modes=('production',), sides=('call',))
        # Exact zero-rate intrinsic and maxima; quote remains an original word.
        for quote in (0., math.nextafter(.25, 0.), .25, math.nextafter(.25, math.inf)):
            add('intrinsic_quote', model, dict(s=1.25, k=1., quote=quote), ('iv',), modes=('iv',))
        for quote in neighbours(1.):
            add('maximum_quote', model, dict(quote=quote), ('iv',), modes=('iv',))
        add('expiry_quote', model, dict(t=0., quote=.125), ('iv',), modes=('iv',))
        # Midpoint-derived financial quotes are filled by the independent
        # reference generator, before any implementation is executed.
        for step in (-1,0,1):
            add('iv_cell_'+str(step), model, dict(s=1., k=1., sigma=math.nextafter(.25, math.inf)), ('iv',), modes=('iv',), sides=('call',))
    for s in neighbours(-1.):
        add('shifted_positivity', 'displaced', dict(s=s, k=0., shift=1.), ('price','delta','iv'), modes=('production',))
    for d in (2.**-1074, 2.**-100, 2.**-53, .1):
        add('sparse_shift', 'displaced', dict(s=1., k=math.nextafter(1., math.inf), shift=d), ('price','delta','rho','veta'))
        add('sparse_maximum', 'displaced', dict(s=2.**64, k=2.**64, shift=d, quote=2.**64), ('iv',), modes=('iv',), sides=('call',))
    maximum = float.fromhex('0x1.fffffffffffffp+1023')
    add('shift_overflow', 'displaced', dict(s=maximum,k=maximum,shift=maximum), ('price','delta'))
    add('distance_overflow', 'bachelier', dict(s=maximum,k=-maximum), ('price','gamma','rho'))
    carry_rates=map(float.fromhex,('0x1p-53','-0x0p+0','-0x1.fffffffffffffp-53'))
    for s,r in zip(neighbours(1.),carry_rates):
        add('carry_cancellation', 'bsm', dict(s=s, k=1., r=r,sigma=0.), ('price','rho','theta'))
    # Arbitrary overlapping low words belong to the enclosure owner. They are
    # not fed to DD primitives whose input contract requires normalization.
    rng = random.Random(SEED)
    word_pairs = [(1.,-1.), (1.,2.**-1074), (2.**-1022,-math.nextafter(2.**-1022,0.)),
                  (maximum,maximum), (1.,.75), (1.,-.75)]
    for _ in range(8 if lane=='smoke' else 128):
        word_pairs.append((math.ldexp(rng.uniform(-1,1),rng.randint(-1020,1020)),
                           math.ldexp(rng.uniform(-1,1),rng.randint(-1020,1020))))
    for hi,lo in word_pairs:
        add('arbitrary_low_words','primitive',dict(s=hi,k=lo),('sum',),modes=('enclosure',),sides=('call',))
    for lower in (1., math.nextafter(1.,math.inf), 2.**-1022):
        add('iv_exact_tie','primitive',dict(s=lower,k=math.nextafter(lower,math.inf)),('iv',),modes=('iv_tie',),sides=('call',))
    # Explicit branch-neighbor coverage, using original financial inputs.
    # Frozen binary64 anchors for .5*sqrt(2), 12*sqrt(2), 27*sqrt(2),
    # and 6. Do not regenerate membership through host libm functions.
    for threshold in map(float.fromhex,('0x1.6a09e667f3bcdp-1','0x1.0f876ccdf6cdap+4','0x1.31785a67b5a75p+5','0x1.8p+2')):
        for sign in (-1.,1.):
            for s in neighbours(sign*threshold):
                add('normal_threshold','bachelier',dict(s=s,k=0.,sigma=1.),
                    ('price','delta','gamma','theta'),sides=('call',))
    # exp(x) anchors for x=eta*sigma and x=eta*sigma*(sigma-2*tau),
    # eta=-13, tau=2*epsilon^(1/16); only negative normalized x is relevant.
    kernel_anchors=((.25,('0x1.3da368521902dp-5',)),
                    (1.,('0x1.2f6053b981d98p-19','0x1.183bc5a80b37bp-11')),
                    (4.,('0x1.f8e6c24b5592ep-76','0x1.608245eb7d069p-269')))
    for model in ('bsm','black76','displaced'):
        for sigma,anchors in kernel_anchors:
            for anchor in anchors:
                for s in neighbours(float.fromhex(anchor)):
                    add('kernel_threshold',model,dict(s=s,k=1.,sigma=sigma),
                        ('price','delta','gamma'),sides=('call',))
        # exp(.25*(d1-.125)), d1 = -6 and +6.
        for anchor in ('0x1.bae93b5663055p-3','0x1.1600da13a93bep+2'):
            for s in neighbours(float.fromhex(anchor)):
                add('normal_dd_threshold',model,dict(s=s,k=1.),
                    ('theta','vanna','color'),sides=('call',))
    add('iv_representability','bachelier',dict(t=16.,quote=2.**-1074),('iv',),modes=('iv',),sides=('call',))
    add('iv_representability','bachelier',dict(t=2.**-1074,quote=maximum),('iv',),modes=('iv',),sides=('call',))
    if lane=='full':
        for model in MODELS:
            for _ in range(48):
                exponent=rng.choice((-1000,-500,-1,0,1,500,1000))
                scale=math.ldexp(1.,exponent)
                add('seeded_mantissas',model,dict(s=scale*rng.uniform(.5,1.),k=scale*rng.uniform(.5,1.),
                    t=rng.choice((2.**-500, .25,1.,4.,2.**500)),
                    sigma=math.ldexp(.125,exponent) if model=='bachelier' else .125,
                    shift=math.ldexp(rng.uniform(-.25,.25),exponent) if model=='displaced' else 0.),
                    ('price',*GREEKS),sides=('call',))
    if len(rows)>MAX_ROWS: raise ValueError('campaign row cap exceeded')
    return rows


def wire(row):
    return ' '.join([row['id'],row['mode'],row['model'],row['side'],row['quantity'],
                     *(row['inputs'][name] for name in FIELDS)])


def fingerprint(row):
    return hashlib.blake2b(wire(row).encode(),digest_size=32).hexdigest()

import re,json,collections
from pathlib import Path
out=Path(__file__).resolve().parent
result={}
for case in ['american-put','cash-terminal-american']:
 counts=collections.Counter()
 for n,stack in re.findall(r'SAMPLES (\d+)\n(.*?)(?=\nSAMPLES |\Z)',(out/(case+'-allocation.log')).read_text(),re.S):
  cat='remaining inverse/price'
  for marker,label in [('interpolate','cash interpolation'),('.prepare','stencil preparation'),('.boundary','boundary arithmetic'),('.slab_constant','time-slab assembly'),('.grid','grid construction')]:
   if marker in stack:cat=label;break
  counts[cat]+=int(n)
 total=sum(counts.values());result[case]=dict(samples=total,categories=dict(counts),percent={k:100*v/total for k,v in counts.items()})
print(json.dumps(result,indent=2))

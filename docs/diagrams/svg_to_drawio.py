#!/usr/bin/env python3
"""Convert this project's rect/text/polyline SVG into native editable draw.io cells.

No raster image or embedded SVG is used. Container hierarchy and explicit
polyline waypoints are retained; wire endpoints on block edges are attached.
"""
from pathlib import Path
from xml.etree import ElementTree as ET
from PIL import ImageFont
import argparse

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('svg',type=Path)
parser.add_argument('--output',type=Path)
args=parser.parse_args()
source=ET.parse(args.svg).getroot()
output=args.output or args.svg.with_suffix('.drawio')
ns=lambda e:e.tag.rsplit('}',1)[-1]
num=lambda e,k,default=0:float(e.get(k,default))
fmt=lambda v:format(v,'.6g')
view=list(map(float,source.get('viewBox').split()))
width,height=view[2:]
mxfile=ET.Element('mxfile',host='app.diagrams.net',agent='UART SVG native conversion',version='24.7.17',type='device',compressed='false')
diagram=ET.SubElement(mxfile,'diagram',id='uart-soc-apb-esp32',name='UART SoC — APB — ESP32')
model=ET.SubElement(diagram,'mxGraphModel',dx=fmt(width),dy=fmt(height),grid='1',gridSize='10',guides='1',tooltips='1',connect='1',arrows='1',fold='0',page='1',pageScale='1',pageWidth=fmt(width),pageHeight=fmt(height),math='0',shadow='0',background='#ffffff')
root=ET.SubElement(model,'root')
ET.SubElement(root,'mxCell',id='0')
ET.SubElement(root,'mxCell',id='1',parent='0')
items=list(next(e for e in source if ns(e)=='g'))
rects=[]
for index,e in enumerate(items):
 if ns(e)!='rect':continue
 x,y,w,h=[num(e,k) for k in ['x','y','width','height']]
 if x==0 and y==0 and w==width and h==height:continue
 rects.append(dict(index=index,id=f'block-{index}',x=x,y=y,w=w,h=h,area=w*h,e=e))
def contains(r,x,y,w=0,h=0):
 return r['x']-.05<=x and r['y']-.05<=y and x+w<=r['x']+r['w']+.05 and y+h<=r['y']+r['h']+.05
def owner(x,y,w=0,h=0,exclude=None):
 candidates=[r for r in rects if r is not exclude and (exclude is None or r['area']>exclude['area']) and contains(r,x,y,w,h)]
 return min(candidates,key=lambda r:r['area']) if candidates else None
byindex={r['index']:r for r in rects}
counts={'blocks':0,'text_lines':0,'connections':0,'attached_ends':0}
def parentcoords(p,x,y):return (x-p['x'],y-p['y']) if p else (x,y)
def cellgeometry(cell,x,y,w,h):
 ET.SubElement(cell,'mxGeometry',x=fmt(x),y=fmt(y),width=fmt(w),height=fmt(h),attrib={'as':'geometry'})
def endpoint(x,y):
 matches=[]
 for r in rects:
  if not contains(r,x,y):continue
  delta=min(abs(x-r['x']),abs(x-r['x']-r['w']),abs(y-r['y']),abs(y-r['y']-r['h']))
  if delta<.1:matches.append(r)
 return min(matches,key=lambda r:r['area']) if matches else None
for index,e in enumerate(items):
 tag=ns(e)
 if tag=='rect' and index in byindex:
  r=byindex[index];p=owner(r['x'],r['y'],r['w'],r['h'],exclude=r)
  x,y=parentcoords(p,r['x'],r['y'])
  style='shape=rectangle;whiteSpace=wrap;html=0;container=1;collapsible=0;recursiveResize=0;'
  style+=f"fillColor={e.get('fill','#fff')};strokeColor={e.get('stroke','#000')};strokeWidth={e.get('stroke-width','1')};"
  radius=num(e,'rx')
  style+=f'rounded={int(radius>0)};'
  if radius:style+=f'absoluteArcSize=1;arcSize={fmt(radius*2)};'
  c=ET.SubElement(root,'mxCell',id=r['id'],value='',style=style,vertex='1',parent=p['id'] if p else '1')
  cellgeometry(c,x,y,r['w'],r['h']);counts['blocks']+=1
 elif tag=='text':
  size=num(e,'font-size',21);bold=e.get('font-weight')=='bold'
  font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans'+('-Bold' if bold else '')+'.ttf',round(size))
  anchor=e.get('text-anchor','start');baseline=num(e,'y');base_x=num(e,'x')
  spans=list(e)
  if not spans:spans=[e]
  for line_no,span in enumerate(spans):
   label=''.join(span.itertext())
   if not label:continue
   sx=num(span,'x',base_x)
   if span is not e:baseline+=num(span,'dy')
   w=font.getlength(label)+12;h=size*1.2
   x=sx-(w/2 if anchor=='middle' else w if anchor=='end' else 0)
   if anchor=='start':x-=1
   y=baseline-size
   p=owner(x,y,w,h)
   x,y=parentcoords(p,x,y)
   style='text;html=0;strokeColor=none;fillColor=none;whiteSpace=nowrap;overflow=visible;spacing=0;verticalAlign=top;'
   style+=f"align={'center' if anchor=='middle' else 'right' if anchor=='end' else 'left'};fontFamily=DejaVu Sans;fontSize={fmt(size)};fontColor={e.get('fill','#172b43')};fontStyle={int(bold)};"
   c=ET.SubElement(root,'mxCell',id=f'text-{index}-{line_no}',value=label,style=style,vertex='1',parent=p['id'] if p else '1',connectable='0')
   cellgeometry(c,x,y,w,h);counts['text_lines']+=1
 elif tag=='polyline':
  points=[tuple(map(float,v.split(','))) for v in e.get('points').split()]
  style=f"edgeStyle=none;rounded=0;html=0;strokeColor={e.get('stroke','#245d85')};strokeWidth={e.get('stroke-width','3')};"
  for attr,arrow in [('marker-start','start'),('marker-end','end')]:
   style+=f'{arrow}Arrow={"block" if e.get(attr) else "none"};{arrow}Fill=1;{arrow}Size=10;'
  if e.get('stroke-dasharray'):style+='dashed=1;dashPattern=9 6;'
  attrs={'id':f'wire-{index}','value':'','edge':'1','parent':'1'}
  for point,attr,prefix in [(points[0],'source','exit'),(points[-1],'target','entry')]:
   r=endpoint(*point)
   if r:
    attrs[attr]=r['id'];counts['attached_ends']+=1
    fx=(point[0]-r['x'])/r['w'];fy=(point[1]-r['y'])/r['h']
    style+=f'{prefix}X={fmt(fx)};{prefix}Y={fmt(fy)};{prefix}Dx=0;{prefix}Dy=0;{prefix}Perimeter=0;'
  c=ET.SubElement(root,'mxCell',**attrs,style=style)
  geo=ET.SubElement(c,'mxGeometry',relative='1',attrib={'as':'geometry'})
  for point,key in [(points[0],'sourcePoint'),(points[-1],'targetPoint')]:
   ET.SubElement(geo,'mxPoint',x=fmt(point[0]),y=fmt(point[1]),attrib={'as':key})
  if len(points)>2:
   array=ET.SubElement(geo,'Array',attrib={'as':'points'})
   for x,y in points[1:-1]:ET.SubElement(array,'mxPoint',x=fmt(x),y=fmt(y))
  counts['connections']+=1
 elif tag not in ('rect','circle'):
  raise ValueError(f'Unsupported SVG element: {tag}')
ET.indent(mxfile,space='  ')
ET.ElementTree(mxfile).write(output,encoding='utf-8',xml_declaration=True)
# Verify all links/parents resolve, graph is acyclic, all graphical objects native.
parsed=ET.parse(output).getroot();cells=parsed.findall('.//mxCell');ids={c.get('id') for c in cells}
assert len(ids)==len(cells)
parents={c.get('id'):c.get('parent') for c in cells}
for c in cells:
 for attr in ['parent','source','target']:
  if c.get(attr):assert c.get(attr) in ids,(c.get('id'),attr)
 ancestors=set();node=c.get('id')
 while node is not None:
  assert node not in ancestors,'Cyclic container parent'
  ancestors.add(node);node=parents.get(node)
 assert 'image=' not in c.get('style','')
assert counts['blocks']==len(rects)
assert counts['connections']==sum(ns(e)=='polyline' for e in items)
print(output)
print(counts)

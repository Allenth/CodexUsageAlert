#!/usr/bin/env python3
"""Produce macOS raster icons from the preserved brand master (requires Pillow).
Only the exterior alpha is cleaned; the logo is not redrawn or recolored.
Usage: python3 scripts/produce_icons.py OUTPUT_DIRECTORY
"""
from pathlib import Path
import json,sys,subprocess
from PIL import Image,ImageDraw,ImageChops

root=Path(__file__).resolve().parents[1]
out=Path(sys.argv[1]).resolve()
out.mkdir(parents=True,exist_ok=True)
source=Image.open(root/'Resources/Brand/AppIcon-source.png').convert('RGBA')
# Measured bounds of the existing backing plate. Its original proportions stay intact.
bounds=(138,145,1117,1073)
mask=Image.new('L',source.size,0)
ImageDraw.Draw(mask).rounded_rectangle(bounds,radius=211,fill=255)
source.putalpha(ImageChops.multiply(source.getchannel('A'),mask))
plate=source.crop(bounds)
plate.thumbnail((824,824),Image.Resampling.LANCZOS)
master=Image.new('RGBA',(1024,1024),(0,0,0,0))
master.alpha_composite(plate,((1024-plate.width)//2,(1024-plate.height)//2))
master.save(out/'AppIcon.png')
iconset=out/'AppIcon.iconset';iconset.mkdir(exist_ok=True)
assets=out/'Assets.xcassets/AppIcon.appiconset';assets.mkdir(parents=True,exist_ok=True)
items=[]
for points in (16,32,128,256,512):
    for scale in (1,2):
        name=f'icon_{points}x{points}'+('@2x' if scale==2 else '')+'.png'
        pixels=points*scale
        icon=master.resize((pixels,pixels),Image.Resampling.LANCZOS)
        icon.save(iconset/name);icon.save(assets/name)
        items.append({'idiom':'mac','size':f'{points}x{points}','scale':f'{scale}x','filename':name})
(assets/'Contents.json').write_text(json.dumps({'images':items,'info':{'author':'xcode','version':1}},indent=2)+'\n')
subprocess.run(['iconutil','-c','icns',str(iconset),'-o',str(out/'AppIcon.icns')],check=True)

# Native system enclosure uses a full-canvas composition, without the legacy inset twice.
native=out/'AppIcon.icon';(native/'Assets').mkdir(parents=True,exist_ok=True)
master.save(native/'Assets/Brand.png')
composition={'fill':{'solid':'srgb:0.03529,0.08235,0.18431,1.00000'},'groups':[{'name':'Original brand artwork','layers':[{'image-name':'Brand.png','name':'Codex C','glass':False,'position':{'scale':1.32,'translation-in-points':[0,0]}}],'specular':False,'shadow':{'kind':'none','opacity':0},'translucency':{'enabled':False,'value':0}}],'supported-platforms':{'squares':['macOS']}}
(native/'icon.json').write_text(json.dumps(composition,indent=2)+'\n')

preview=Image.new('RGB',(800,320),'#e6e8ed')
ImageDraw.Draw(preview).rectangle((400,0,800,320),fill='#10141d')
for x0 in (0,400):
    x=x0+20
    for size in (20,32,64,128):
        icon=master.resize((size,size),Image.Resampling.LANCZOS)
        preview.paste(icon,(x,90+(128-size)//2),icon)
        x+=size+24
preview.save(out/'preview-light-dark.png')
print(out)

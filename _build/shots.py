import asyncio,sys
from playwright.async_api import async_playwright
PAGES=[("home","/"),("newco","/newco/"),("conferences","/conferences/"),("news","/news/"),("article","/news/haisco-sentivera-newco.html")]
async def main():
    async with async_playwright() as p:
        b=await p.chromium.launch()
        for vw,(w,h,mob) in {"desktop":(1280,900,False),"mobile":(390,844,True)}.items():
            ctx=await b.new_context(viewport={"width":w,"height":h},device_scale_factor=1 if not mob else 2,is_mobile=mob,has_touch=mob)
            pg=await ctx.new_page(); errs=[]
            pg.on("pageerror",lambda e:errs.append(str(e)))
            pg.on("console",lambda m:errs.append(m.text) if m.type=="error" else None)
            for name,path in PAGES:
                await pg.goto("http://127.0.0.1:8931"+path,wait_until="networkidle")
                await pg.wait_for_timeout(400)
                ow=await pg.evaluate("document.documentElement.scrollWidth")
                await pg.screenshot(path=f"_shots/{name}_{vw}.png",full_page=True)
                print(name,vw,"scrollWidth",ow,errs); errs.clear()
            await ctx.close()
        await b.close()
asyncio.run(main())

import asyncio,sys
from playwright.async_api import async_playwright
async def main():
    async with async_playwright() as p:
        b=await p.chromium.launch(); pg=await (await b.new_context(viewport={"width":390,"height":844},is_mobile=True)).new_page()
        for path in sys.argv[1:]:
            await pg.goto("http://127.0.0.1:8931"+path,wait_until="networkidle")
            r=await pg.evaluate("""()=>[...document.querySelectorAll('body *')].filter(e=>e.getBoundingClientRect().right>392).slice(0,12).map(e=>e.tagName+'.'+e.className+' '+Math.round(e.getBoundingClientRect().right)+' '+(e.textContent||'').slice(0,40))""")
            print(path); [print(' ',x) for x in r]
        await b.close()
asyncio.run(main())

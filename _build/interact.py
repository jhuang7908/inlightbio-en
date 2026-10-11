import asyncio
from playwright.async_api import async_playwright
B="http://127.0.0.1:8931"
async def main():
    async with async_playwright() as p:
        b=await p.chromium.launch(); pg=await (await b.new_context(viewport={"width":1280,"height":900})).new_page()
        errs=[]; pg.on("pageerror",lambda e:errs.append(str(e)))
        await pg.goto(B+"/conferences/",wait_until="networkidle")
        print("all:",await pg.inner_text("#confcount"))
        await pg.click("#confcal summary"); await pg.wait_for_timeout(200)
        await pg.screenshot(path="_shots/conferences_desktop_calendar_open.png",clip={"x":0,"y":0,"width":1280,"height":700})
        await pg.click('#confrange button[data-r="3"]'); print("3mo:",await pg.inner_text("#confcount"))
        await pg.click("#confcal summary"); await pg.click('#confkind button[data-k="Partnering"]'); print("3mo partnering:",await pg.inner_text("#confcount"), await pg.inner_text("#confcallabel"))
        await pg.click("#confcal summary"); await pg.click('#confrange button[data-r="all"]'); await pg.click("#confcal summary"); await pg.click('#confkind button[data-k="all"]')
        await pg.click("#confcal summary"); await pg.click('#confsort button[data-o="desc"]')
        print("desc first:", (await pg.inner_text("#conflist .confrow h3")))
        await pg.goto(B+"/news/",wait_until="networkidle")
        await pg.click("#nfcal summary"); await pg.wait_for_timeout(200)
        await pg.screenshot(path="_shots/news_desktop_filter_open.png",clip={"x":0,"y":300,"width":1280,"height":700})
        await pg.click('#nf-type button[data-g="newco"]'); print("newco:",await pg.inner_text("#newscount"))
        await pg.click('#newsfeed .item:not([hidden]) .expbtn'); await pg.wait_for_timeout(200)
        print("panel:",await pg.locator(".feed-details-panel").count())
        await pg.screenshot(path="_work/crops/news_panel.png",full_page=False)
        print("errors",errs); await b.close()
asyncio.run(main())

#!/usr/bin/env python3
"""Render copied dashboard QML against inert Quickshell fixtures with PySide6."""
import argparse, json, os, sys, traceback, tempfile, shutil, time, statistics
from pathlib import Path
os.environ['TZ']='UTC'
time.tzset()
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
os.environ.setdefault('QT_QUICK_BACKEND','software')
os.environ.setdefault('QML_XHR_ALLOW_FILE_READ','1')
from PySide6.QtCore import QUrl, QTimer, QPointF, QPoint, QRect, Qt, qInstallMessageHandler
from PySide6.QtTest import QTest
from PySide6.QtGui import QGuiApplication, QFontDatabase, QImage, QColor, QPainter, QPen, QBrush
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow, QQuickItem
import shiboken6
parser=argparse.ArgumentParser(description="Headless dashboard theme/render fixture; no live desktop or commands")
parser.add_argument('--repo',type=Path,default=Path(__file__).resolve().parents[1])
parser.add_argument('--output-dir',type=Path)
parser.add_argument('--font-dir',type=Path)
args=parser.parse_args()
repo=args.repo.resolve(); fixtures=Path(__file__).resolve().parent/'fixtures/dashboard'
H=Path(tempfile.mkdtemp(prefix='dashboard-render-'))
shutil.copytree(fixtures/'app',H/'app'); shutil.copytree(fixtures/'imports',H/'imports')
(H/'out').mkdir(); (H/'state').mkdir(); (H/'home/.config/hypr/themes/.active').mkdir(parents=True)
qs=repo/'quickshell/.config/quickshell'
for f in qs.iterdir():
    if f.name.startswith('Dash') or f.name in ['Gauge.qml','Sparkline.qml','WaveProgress.qml','Theme.qml','SysState.qml','WeatherState.qml','Holidays.js','IconButton.qml','VolumeSlider.qml','LyricsView.qml']:
        shutil.copyfile(f,H/'app'/f.name)
sys.path.insert(0,str(repo/'hypr/.config/hypr/theme'))
import themelib
for slug in ['tokyo-night','catppuccin-latte']:
    theme=themelib.load(repo/f'hypr/.config/hypr/themes/{slug}/colors.toml')
    (H/f'{slug}.json').write_text(themelib.render((repo/'hypr/.config/hypr/theme/templates/quickshell-theme.json').read_text(),theme))
(H/'home/.config/hypr/themes/.active/theme.json').write_text((H/'tokyo-night.json').read_text())
DARK_ACCENT=json.loads((H/'tokyo-night.json').read_text())['colors']['accent']
LIGHT_ACCENT=json.loads((H/'catppuccin-latte.json').read_text())['colors']['accent']
image=QImage(512,512,QImage.Format_ARGB32); image.fill(QColor('#1d1b2e'))
painter=QPainter(image); painter.setRenderHint(QPainter.Antialiasing)
painter.setPen(QPen(QColor('#3a3656'),6)); painter.setBrush(Qt.NoBrush)
for r in range(60,700,34): painter.drawEllipse(QRect(330-r,220-r,2*r,2*r))
painter.setPen(Qt.NoPen); painter.setBrush(QColor('#c4a7e7')); painter.drawEllipse(QRect(250,80,220,220)); painter.end(); image.save(str(H/'art.png'))
messages=[]
def logging(kind,ctx,message):
    messages.append(message)
    if 'QML' in message or 'Error' in message or 'Reference' in message: print(message,flush=True)
qInstallMessageHandler(logging)
app=QGuiApplication(sys.argv)
for name in ['JetBrainsMonoNerdFont-Regular.ttf','JetBrainsMonoNerdFont-Bold.ttf']:
    if args.font_dir: QFontDatabase.addApplicationFont(str(args.font_dir/name))
engine=QQmlApplicationEngine(); engine.addImportPath(str(H/'imports')); engine.rootContext().setContextProperty('fixtureRoot',str(H))
engine.load(QUrl.fromLocalFile(str(H/'app/main.qml')))
assert engine.rootObjects(),'QML load failed: '+repr(messages)
win=shiboken6.wrapInstance(shiboken6.getCppPointer(engine.rootObjects()[0])[0],QQuickWindow)
def nodes(root):
    yield root
    for child in root.children(): yield from nodes(child)
def ptr(obj): return shiboken6.getCppPointer(obj)[0]
def kind(obj): return obj.metaObject().className()
def page_ids():
    return {kind(o).split('_QML')[0]:ptr(o) for o in nodes(win) if kind(o).startswith(('DashOverview_','DashMedia_','DashSystem_','DashWeather_'))}
def rgba_bytes(color):
    c=QColor(color); return bytes([c.red(),c.green(),c.blue(),255])
def count_color(image,color):
    im=image.convertToFormat(QImage.Format_RGBA8888)
    return bytes(im.constBits()).count(rgba_bytes(color))
def canvases(image):
    out={}
    for obj in nodes(win):
        if 'Canvas' not in kind(obj): continue
        item=shiboken6.wrapInstance(ptr(obj),QQuickItem)
        if not item.isVisible() or item.width()<1 or item.height()<1: continue
        xy=item.mapToScene(QPointF(0,0))
        rect=QRect(round(xy.x()),round(xy.y()),round(item.width()),round(item.height())).intersected(image.rect())
        if rect.isEmpty(): continue
        crop=image.copy(rect)
        out[str(ptr(obj))]={'class':kind(obj),'rect':[rect.x(),rect.y(),rect.width(),rect.height()],
            'dark_accent_pixels':count_color(crop,DARK_ACCENT),'light_accent_pixels':count_color(crop,LIGHT_ACCENT)}
    return out
TABS=['overview','media','system','weather']; snapshots={}; report={'fixture':'Copied production QML, inert IO Process, async-completion fixture FileView, same Qt Quick window','checks':[]}
start_ids=None; stage={'i':0,'phase':'dark'}
def fail(exc):
    traceback.print_exc(); report['failure']=str(exc); (H/'report.json').write_text(json.dumps(report,indent=2)); app.exit(1)
def capture():
    try:
        tab=TABS[stage['i']]; phase=stage['phase']; image=win.grabWindow(); assert not image.isNull()
        path=H/f'out/{tab}-{phase}.png'; assert image.save(str(path)); snapshots[(phase,tab)]=canvases(image)
        assert page_ids()==start_ids,'Page QObjects recreated'
        palette=json.loads((H/('tokyo-night.json' if phase=='dark' else 'catppuccin-latte.json')).read_text())
        assert win.property('fixtureView').property('radius')==max(0,palette['style']['rounding']),'Menu rounding did not follow palette'
        assert snapshots[(phase,tab)],f'{tab} has no rendered Canvas fixture'
        report['checks'].append({'phase':phase,'tab':tab,'page_ids_retained':True,'image':[image.width(),image.height()],'canvases':snapshots[(phase,tab)]})
        stage['i']+=1
        if stage['i']<4:
            win.setProperty('tab',TABS[stage['i']]); QTimer.singleShot(450,capture); return
        if phase=='dark':
            fixture=H/'home/.config/hypr/themes/.active/theme.json'
            fixture.write_text((H/'catppuccin-latte.json').read_text())
            win.reloadPalette(); QTest.qWait(80); assert win.property('themeSlug')=='catppuccin-latte','Actual Theme reload failed'
            stage.update(i=0,phase='light'); win.setProperty('tab',TABS[0]); QTimer.singleShot(550,capture); return
        for tab in TABS:
            dark=snapshots[('dark',tab)]; light=snapshots[('light',tab)]
            assert dark.keys()==light.keys(),f'{tab}: Canvas instances recreated'
            for canvas_id,before in dark.items():
                after=light[canvas_id]
                assert before['dark_accent_pixels']>0,f'{tab}: no original accent in Canvas {canvas_id}'
                assert after['light_accent_pixels']>0,f'{tab}: Canvas {canvas_id} did not repaint new accent'
                assert after['dark_accent_pixels']==0,f'{tab}: Canvas {canvas_id} retained old accent'
        report['canvas_live_repaint']='passed for all visible canvases on all four retained pages'
        # Change palettes while unmapped and verify cached canvases on reopening.
        for slug,field in [('tokyo-night','dark_accent_pixels'),('catppuccin-latte','light_accent_pixels')]:
            win.setProperty('fixtureShown',False); win.hide(); app.processEvents()
            (H/'home/.config/hypr/themes/.active/theme.json').write_text((H/f'{slug}.json').read_text())
            win.reloadPalette(); QTest.qWait(80); assert win.property('themeSlug')==slug
            win.show(); win.setProperty('fixtureShown',True); QTest.qWait(200)
            for tab in TABS:
                win.setProperty('tab',tab); QTest.qWait(180)
                cached=canvases(win.grabWindow()); assert cached.keys()==snapshots[('dark',tab)].keys(),f'{tab}: cached Canvas missing after reopening'
                assert all(c[field]>0 for c in cached.values()),f'{tab}: cached colors stale after hidden reload'
                assert page_ids()==start_ids
        report['hidden_palette_reload']='passed both palettes on all 4 retained pages after reopening'
        win.setScale(1.5); win.setProperty('viewportWidth',720); win.setProperty('viewportHeight',490)
        stage.update(i=0,phase='narrow'); win.setProperty('tab','overview'); QTimer.singleShot(600,capture_narrow)
    except Exception as exc: fail(exc)
def capture_narrow():
    try:
        tab=TABS[stage['i']]; image=win.grabWindow(); assert image.save(str(H/f'out/{tab}-narrow.png'))
        assert image.width()==768 and image.height()==538
        assert page_ids()==start_ids
        report['checks'].append({'phase':'narrow','tab':tab,'page_ids_retained':True,'image':[image.width(),image.height()]})
        stage['i']+=1
        if stage['i']<4: win.setProperty('tab',TABS[stage['i']]); QTimer.singleShot(450,capture_narrow); return
        # Verify real narrow tab hit areas and both scroll directions.
        view=win.property('fixtureView'); pad=view.property('pad'); tab_h=view.property('tabH')
        for i,tab in enumerate(TABS):
            x=round(24+pad+(view.width()-2*pad)*(i+0.5)/4)
            y=round(24+pad+tab_h/2)
            QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,QPoint(x,y))
            assert win.property('selectedTab')==tab,f'{tab} tab is not clickable in narrow window'
        flicks=[o for o in view.children() if o.inherits('QQuickFlickable')]
        assert len(flicks)==1,'Missing body Flickable'
        flick=flicks[0]
        assert flick.property('interactive') and flick.property('contentWidth')>flick.property('width') and flick.property('contentHeight')>flick.property('height'),'Narrow body does not scroll both directions'
        flick.setProperty('contentX',flick.property('contentWidth')-flick.property('width'))
        flick.setProperty('contentY',flick.property('contentHeight')-flick.property('height'))
        app.processEvents(); QTest.qWait(200)
        assert win.grabWindow().save(str(H/'out/weather-narrow-scrolled.png'))
        report['narrow_navigation']='all 4 tab click targets reachable; body scrolls horizontally and vertically'
        # Contact sheet with one row per tab and before/after side-by-side.
        first=QImage(str(H/'out/overview-dark.png')); sheet=QImage(first.width()*2,first.height()*4,QImage.Format_ARGB32); sheet.fill(QColor('#12131b'))
        painter=QPainter(sheet)
        for i,tab in enumerate(TABS):
            for j,phase in enumerate(['dark','light']): painter.drawImage(j*first.width(),i*first.height(),QImage(str(H/f'out/{tab}-{phase}.png')))
        painter.end(); sheet.save(str(H/'out/theme-switch-contact-sheet.png'))
        # Timings describe this normal offscreen Qt window, not a Wayland popup.
        win.setScale(1.0); win.setProperty('viewportWidth',0); win.setProperty('viewportHeight',0)
        flick.setProperty('contentX',0); flick.setProperty('contentY',0); QTest.qWait(200)
        def next_frame(action):
            done=[]
            def swapped(): done.append(time.perf_counter())
            win.frameSwapped.connect(swapped); started=time.perf_counter(); action(); win.requestUpdate()
            while not done and time.perf_counter()-started<2: QTest.qWait(1)
            win.frameSwapped.disconnect(swapped); assert done,'No Qt frame presented'
            return (done[0]-started)*1000
        switches=[next_frame(lambda tab=tab:win.setProperty('tab',tab)) for tab in (TABS[1:]+TABS[:1])*5]
        opens=[]
        for _ in range(10):
            win.setProperty('fixtureShown',False); win.hide(); QTest.qWait(20)
            opens.append(next_frame(lambda:(win.setProperty('fixtureShown',True),win.show())))
        report['timings_ms']={'environment':'offscreen software renderer, normal Qt window; no Wayland compositor',
            '20_tab_switches':{'median':statistics.median(switches),'max':max(switches)},
            '10_opens':{'median':statistics.median(opens),'max':max(opens)}}
        assert page_ids()==start_ids
        win.missingData()
        for tab in ['overview','system','weather','media']:
            win.setProperty('tab',tab); QTest.qWait(200); assert win.grabWindow().save(str(H/f'out/{tab}-missing-data.png'))
        errors=[m for m in messages if any(s in m for s in ['ReferenceError','TypeError','Unable to assign','Cannot assign','is not a type','Binding loop'])]
        assert not errors,'QML runtime errors: '+repr(errors)
        report['qml_errors']=errors; report['retained_page_ids']=start_ids
        (H/'report.json').write_text(json.dumps(report,indent=2))
        if args.output_dir:
            args.output_dir.mkdir(parents=True,exist_ok=True)
            shutil.copytree(H/'out',args.output_dir,dirs_exist_ok=True); shutil.copyfile(H/'report.json',args.output_dir/'report.json')
        print(json.dumps({'result':'PASS','artifacts':str(H/'out'),'report':str(H/'report.json'),'pages_retained':start_ids},indent=2),flush=True); app.quit()
    except Exception as exc: fail(exc)
def begin():
    global start_ids
    start_ids=page_ids(); assert len(start_ids)==4,start_ids
    capture()
QTimer.singleShot(900,begin); QTimer.singleShot(60000,lambda: fail(RuntimeError('fixture timeout')))
sys.exit(app.exec())

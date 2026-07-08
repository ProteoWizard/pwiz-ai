#!/usr/bin/env python3
"""Render model-diagnostics HTML views to PNG via headless Chrome.

Injects a tiny driver script that activates a tab and (optionally) triggers an
interaction (select an FDR pass view, or click a feature row), then screenshots.

Usage: python shot-mdiag.py <html> <outdir> <stem>
Produces <stem>_fdr_pass2.png, <stem>_fdr_pass1.png, <stem>_model_feature.png
"""
import os, re, subprocess, sys, tempfile

CHROME = r"C:/Program Files/Google/Chrome/Application/chrome.exe"

def driver(js):
    return "<script>window.addEventListener('load',function(){setTimeout(function(){" + js + "},60);});</script>"

# click a nav button by its visible text
CLICK_TAB = "for(const b of document.querySelectorAll('nav button')){if(b.textContent.trim()==='%s'){b.click();break;}}"
# click an FDR view-selector button whose label contains a substring
CLICK_VIEW = "for(const b of document.querySelectorAll('#fdpViewSel button')){if(b.textContent.indexOf('%s')>=0){b.click();break;}}"
# click the first clickable feature row
CLICK_FEAT = "var r=document.querySelector('#modelTable tr.clk');if(r)r.click();"

# toggle a legend entry off by its visible text within a legend container
CLICK_LEG = "for(const sp of document.querySelectorAll('#%s span')){if(sp.textContent.indexOf('%s')>=0){sp.click();break;}}"

SHOTS = [
    ("fdr_pass2",  (CLICK_TAB % "FDR calibration") + (CLICK_VIEW % "Pass 2 - experiment")),
    ("fdr_pass1",  (CLICK_TAB % "FDR calibration") + (CLICK_VIEW % "Pass 1 - experiment")),
    ("model_feature", (CLICK_TAB % "Model") + CLICK_FEAT),
    ("model_composite", (CLICK_TAB % "Model")),
    ("model_expanded", (CLICK_TAB % "Model") + "document.getElementById('modelToggle').click();"),
    ("composite_nonorm", (CLICK_TAB % "Model") + (CLICK_LEG % ("scoreLegend", "decoy normal"))),
    ("competition_toggle", (CLICK_TAB % "Competition") + (CLICK_LEG % ("wfLegend", "real pairs"))),
    ("summary", (CLICK_TAB % "Summary")),
    # dual-model (only meaningful when a 2nd Percolator ran, i.e. --protein-fdr)
    ("model_pass2", (CLICK_TAB % "Model") +
        "for(const b of document.querySelectorAll('#modelPassSel button')){if(b.textContent.indexOf('2nd pass')>=0){b.click();break;}}"),
]

def main():
    html_path, outdir, stem = sys.argv[1], sys.argv[2], sys.argv[3]
    html = open(html_path, encoding="utf-8").read()
    os.makedirs(outdir, exist_ok=True)
    for name, js in SHOTS:
        patched = html.replace("</body>", driver(js) + "</body>", 1)
        tmp = os.path.join(tempfile.gettempdir(), f"_mdiagshot_{stem}_{name}.html")
        open(tmp, "w", encoding="utf-8").write(patched)
        out = os.path.join(outdir, f"{stem}_{name}.png")
        cmd = [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
               "--force-color-profile=srgb", "--window-size=1280,2400",
               f"--screenshot={out}", "--virtual-time-budget=3000",
               "file:///" + tmp.replace("\\", "/")]
        r = subprocess.run(cmd, capture_output=True, text=True)
        ok = os.path.exists(out) and os.path.getsize(out) > 0
        print(f"{name}: {'OK '+str(os.path.getsize(out))+'b' if ok else 'FAILED '+r.stderr[-200:]}")

if __name__ == "__main__":
    main()

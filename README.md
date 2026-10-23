# 🔗 HOL Link Checker

A simple command-line tool that scans a website for **broken links** and shows the results in a clear, visual report in your browser.

Give it a website address. It crawls the pages on that site, checks every link, image, script and stylesheet it finds, and tells you exactly what's broken and where to find it.

---

## ✨ Features

- **Crawls your whole site.** It follows links between pages on the same website, up to a page limit you choose.
- **Checks everything.** Normal links, images, scripts and stylesheets, including links to other websites.
- **Fast.** Links are checked in parallel.
- **Polite.** It pauses briefly between pages so it doesn't overload the site, and it never crawls other people's websites.
- **Visual HTML report** that opens automatically in your browser, with:
  - A clear red or green summary banner
  - Clickable filters for Broken, Needs a look, Redirects and Working links
  - A search bar
  - Plain-English explanations of each problem
  - The page (and link text) where each link was found, so you can fix it
  - An **Export CSV** button
  - Automatic dark mode
- **Plain-text output** as well: a summary in the terminal and a `broken-links.txt` file.

---

## 📋 Requirements

- **macOS or Linux** (Windows works through [WSL](https://learn.microsoft.com/windows/wsl/))
- **Python 3**, which is usually already installed on macOS and Linux

To check you have Python 3, run:

```bash
python3 --version
```

No extra Python packages are needed. The tool only uses Python's built-in libraries.

---

## 🚀 Installation

1. **Download the project.** Click **Code → Download ZIP** on GitHub, unzip it, then open a terminal in the unzipped folder.

2. **Make the script executable** (you only need to do this once):

   ```bash
   chmod +x holLinkChecker.sh
   ```

---

## 🛠️ Usage

Run the script from the project folder:

```bash
./holLinkChecker.sh
```

You'll be asked three things:

| Prompt | What to enter |
|---|---|
| `Enter website URL:` | The site to check, e.g. `example.com` or `https://example.com`. `https://` is added for you if you leave it out. |
| `Max pages to scan [100]:` | How many pages to crawl. Press **Enter** for the default of 100. |
| `Start scan? (y/n):` | Type `y` to start, or `n` to cancel. |

### Example

```text
====================================
        HOL LINK CHECKER
====================================

Enter website URL: example.com
Max pages to scan [100]:

Website: https://example.com
Maximum pages: 100

Start scan? (y/n): y

Scanning https://example.com (up to 100 pages)...

  Pages scanned: 12   Links found: 148
  Checking links [##############################] 148/148

  Broken:       3
  Needs a look: 1
  Redirects:    9
  Working:      135

  Broken links found:

  [404] https://example.com/old-page
    Found on: https://example.com/about (+2 more)
  ...

  Text list saved to:  broken-links.txt
  Visual report:       /path/to/holLinkChecker/reports/linkreport_example.com_20261023_190600.html
```

The visual report then opens in your default browser.

---

## 📊 Understanding the results

| Category | Meaning | What to do |
|---|---|---|
| 🔴 **Broken** | The link doesn't work. The page doesn't exist (e.g. `404`), the server returned an error (e.g. `500`), or the site couldn't be reached. | Fix or remove the link. |
| 🟠 **Needs a look** | The site refused the checker (`401`, `403` or `429`). This is usually bot protection, and the link often works fine for real visitors. | Open the link yourself to confirm. |
| 🔵 **Redirect** | The link works, but sends visitors on to a different address. | Optional: update the link to point straight to the final address. |
| 🟢 **Working** | The link is fine. | Nothing. |

---

## 📁 Output files

You can download a full spreadsheet of every link using the **Export CSV** button in the visual report.

---

## ❓ Troubleshooting

**`permission denied: ./holLinkChecker.sh`**
Run `chmod +x holLinkChecker.sh` first, or start it with `bash holLinkChecker.sh`.

**`Error: python3 is required but was not found.`**
Install Python 3 from [python.org](https://www.python.org/downloads/). On a Mac you can also use `brew install python`.

**`Couldn't open https://...`**
Check the address is correct and that the site loads in your browser. Some sites block automated tools entirely.

**SSL / certificate errors on macOS**
If every HTTPS link shows as broken with a certificate error, your Python install may be missing its certificates. Run the **Install Certificates.command** file found in your `Applications/Python 3.x` folder.

**A link shows as broken or "Needs a look" but works in my browser**
Some sites block automated requests or behave differently for bots. Open the link manually to double-check.

**The report didn't open automatically**
Open the `.html` file from the `reports/` folder in any web browser. Its full path is printed at the end of the scan.

---

## ⚠️ Responsible use

Only scan websites you own or have permission to test. The checker is built to be gentle, but scanning large sites repeatedly can still put load on someone else's server.

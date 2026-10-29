"""Create, update or attach files to a LabKey wiki page from the command line.

The same functions the MCP tools create_wiki_page, update_wiki_page and attach_wiki_files
call, for a session whose MCP server predates them (it picks up new tools only after a
Claude Code restart) and for scripted publishing. Credentials come from the netrc entry
for the server, as for the MCP.

    python scripts/wiki_publish.py create  --page CarafeLibraryBuild --title "..." --body page.md \\
        --container /home/software/Skyline-dev-private [--renderer MARKDOWN] [--hide-attachments]
    python scripts/wiki_publish.py update  --page CarafeLibraryBuild --body page.md [--title "..."] \\
        [--show-attachments | --hide-attachments]
    python scripts/wiki_publish.py attach  --page CarafeLibraryBuild shot1.png shot2.png ...

Run it from any directory; it adds the LabKeyMcp folder to the import path itself. From
Git Bash, prefix the command with MSYS_NO_PATHCONV=1 so the container path is not rewritten.
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from tools.common import DEFAULT_SERVER, DEFAULT_WIKI_CONTAINER  # noqa: E402
from tools.wiki import attach_wiki_files, create_wiki_page, save_wiki_page  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("action", choices=["create", "update", "attach"])
    parser.add_argument("files", nargs="*", help="Files to attach (attach only)")
    parser.add_argument("--page", required=True, help="Wiki page name (the name= in its URL)")
    parser.add_argument("--title", help="Page title (required for create)")
    parser.add_argument("--body", help="File holding the page body (create and update)")
    parser.add_argument("--renderer", default="MARKDOWN", help="HTML, MARKDOWN, RADEOX or TEXT_WITH_LINKS (create)")
    parser.add_argument("--server", default=DEFAULT_SERVER)
    parser.add_argument("--container", default=DEFAULT_WIKI_CONTAINER)
    visibility = parser.add_mutually_exclusive_group()
    visibility.add_argument("--show-attachments", dest="show_attachments", action="store_true", default=None,
                            help="List the attachments under the page (the default for a new page)")
    visibility.add_argument("--hide-attachments", dest="show_attachments", action="store_false",
                            help="Do not list the attachments under the page (screenshots referenced in the body)")
    args = parser.parse_args()

    if args.action in ("create", "update"):
        if not args.body:
            parser.error(f"{args.action} needs --body")
        body = Path(args.body).read_text(encoding="utf-8")
    if args.action == "create":
        if not args.title:
            parser.error("create needs --title")
        show = True if args.show_attachments is None else args.show_attachments
        result = create_wiki_page(args.page, body, args.title, args.renderer, show, args.server, args.container)
        print(f"Created {args.page} (version {result['version']}, entityId {result.get('entityId') or '(not reported)'})")
    elif args.action == "update":
        result = save_wiki_page(args.page, body, args.title, args.show_attachments, args.server, args.container)
        print(f"Updated {args.page}: version {result['old_version']} -> {result['new_version']}")
    else:
        if not args.files:
            parser.error("attach needs at least one file")
        result = attach_wiki_files(args.page, args.files, args.server, args.container)
        print(f"Attached: {', '.join(result['uploaded'])}")
        print(f"Page attachments: {', '.join(result['attachments'])}")
    print(f"View at: {result['url']}")


if __name__ == "__main__":
    main()

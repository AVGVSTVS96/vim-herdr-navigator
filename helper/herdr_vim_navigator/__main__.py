"""Allow ``python -m herdr_vim_navigator`` to run the CLI."""

from .cli import main

if __name__ == "__main__":
    raise SystemExit(main())

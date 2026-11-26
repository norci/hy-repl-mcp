# Install Hy's import hook before importing .hy submodules.
import hy  # noqa: F401

from . import server


def main():
    server.main()


if __name__ == "__main__":
    main()

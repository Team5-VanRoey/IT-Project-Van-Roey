#!/bin/sh
# Activates the Git hooks in .githooks/. Every team member runs this once after cloning.
#
# Usage (from inside the repo, on Windows use Git Bash):
#   sh scripts/002_setup_hooks.sh

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Run this inside the repository."; exit 1; }

git config core.hooksPath .githooks
chmod +x .githooks/* scripts/*.sh 2>/dev/null

echo "Git hooks activated (core.hooksPath = .githooks)."
echo "- commits on main/develop and wrong branch names are rejected"
echo "- commit messages must start with IT2627T05-XX:"
echo "- pushes to main/develop and deleting remote branches are rejected"
echo ""
echo "Verify with: sh scripts/003_test_hooks.sh"

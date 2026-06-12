#!/bin/sh
# Install git hooks for this project.
# Run once after cloning: sh scripts/setup-hooks.sh

HOOKS_DIR="$(git rev-parse --show-toplevel)/.git/hooks"

cat > "$HOOKS_DIR/pre-commit" << 'EOF'
#!/bin/sh
# Pre-commit: run stylua format check on staged Lua files

STAGED=$(git diff --cached --name-only --diff-filter=ACM | grep '\.lua$')

if [ -z "$STAGED" ]; then
  exit 0
fi

if ! command -v stylua > /dev/null 2>&1; then
  echo "stylua not found. Install it: https://github.com/JohnnyMorganz/StyLua/releases"
  exit 1
fi

echo "Running stylua check..."
echo "$STAGED" | xargs stylua --check

if [ $? -ne 0 ]; then
  echo ""
  echo "stylua format check failed. Run: stylua lua/ tests/"
  exit 1
fi
EOF

chmod +x "$HOOKS_DIR/pre-commit"
echo "Git hooks installed successfully."

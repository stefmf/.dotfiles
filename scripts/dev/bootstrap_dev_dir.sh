#!/usr/bin/env bash
# Idempotent dev workspace bootstrapper
# Creates ~/dev structure and seeds templates if missing

set -e

DEV_ROOT="$HOME/dev"
TEMPLATE_SRC="${DOTFILES:-$HOME/.dotfiles}/dev-templates"

# Create main structure
mkdir -p "$DEV_ROOT/projects/example/repos" \
         "$DEV_ROOT/projects/example/ops" \
         "$DEV_ROOT/projects/example/infra" \
         "$DEV_ROOT/projects/example/env" \
         "$DEV_ROOT/projects/example/scripts" \
         "$DEV_ROOT/projects/example/docs" \
         "$DEV_ROOT/projects/example/agent" \
         "$DEV_ROOT/projects/example/logs" \
         "$DEV_ROOT/repos" \
         "$DEV_ROOT/sandbox" \
         "$DEV_ROOT/stacks/containers" \
         "$DEV_ROOT/stacks/cloud" \
         "$DEV_ROOT/stacks/k8s" \
         "$DEV_ROOT/logs/containers" \
         "$DEV_ROOT/logs/cloud" \
         "$DEV_ROOT/logs/sandbox" \
         "$DEV_ROOT/logs/misc" \
         "$DEV_ROOT/templates/project" \
         "$DEV_ROOT/templates/repo" \
         "$DEV_ROOT/templates/stack" \
         "$DEV_ROOT/notes/snippets" \
         "$DEV_ROOT/notes/prompts" \
         "$DEV_ROOT/data"

# Copy template files if not present
copy_if_missing() {
  src="$1"
  dest="$2"
  if [ ! -e "$dest" ] && [ -e "$src" ]; then
    cp "$src" "$dest"
    echo "Seeded $dest"
  fi
}

# Seed example project and templates (assumes templates are in $TEMPLATE_SRC)
copy_if_missing "$TEMPLATE_SRC/projects/example/README.md" "$DEV_ROOT/projects/example/README.md"
copy_if_missing "$TEMPLATE_SRC/projects/example/ops/Makefile" "$DEV_ROOT/projects/example/ops/Makefile"
copy_if_missing "$TEMPLATE_SRC/projects/example/ops/docker-compose.yml" "$DEV_ROOT/projects/example/ops/docker-compose.yml"
copy_if_missing "$TEMPLATE_SRC/projects/example/env/.envrc" "$DEV_ROOT/projects/example/env/.envrc"
copy_if_missing "$TEMPLATE_SRC/projects/example/env/.env.example" "$DEV_ROOT/projects/example/env/.env.example"

# Seed template skeletons
for t in project repo stack; do
  copy_if_missing "$TEMPLATE_SRC/templates/$t/README.md" "$DEV_ROOT/templates/$t/README.md"
done

# Seed README for dev root
copy_if_missing "$TEMPLATE_SRC/README.md" "$DEV_ROOT/README.md"

# Optionally seed other README files as needed

# Done

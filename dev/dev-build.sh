#!/bin/bash
# Redirect all output to build.log while still printing to terminal.
exec > >(tee build.log) 2>&1

set -e

######################################
# Get Environment and Script Directories
######################################
# Get the directory where this script is located.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Assume the .env file is in the project root (one level up from the script directory).
ENV_FILE="${SCRIPT_DIR}/../.env"

# Source environment variables from the .env file.
if [ -f "$ENV_FILE" ]; then
  echo "Sourcing environment variables from $ENV_FILE"
  set -o allexport
  source "$ENV_FILE"
  set +o allexport
else
  echo ".env file not found at $ENV_FILE!"
  exit 1
fi

# Change directory to the project root.
cd "${SCRIPT_DIR}/.."

######################################
# Warning and Cleanup Confirmation
######################################
echo "WARNING: This will delete previous containers and persistent volumes. This action will delete your database!"
read -p "Do you want to proceed with deletion? [y/N]: " CONFIRM
if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Proceeding with cleanup..."
  
  echo "Stopping running containers and removing volumes..."
  docker-compose down -v

  echo "Pruning unused Docker images..."
  docker image prune -a -f

  echo "Removing local directories (invoiceplane_* and mariadb)..."
  sudo rm -rf invoiceplane_* mariadb
else
  echo "Cleanup aborted. Exiting build."
  exit 1
fi

######################################
# Enable Docker BuildKit
######################################
export DOCKER_BUILDKIT=1

######################################
# Interactive Prompt: Push Option
######################################
# Ask the user if they want to push the built image to GitHub & Docker Hub.
read -p "Do you want to push the image to GitHub & Docker Hub after building? [y/N]: " PUSH_RESPONSE
if [[ "$PUSH_RESPONSE" =~ ^[Yy]$ ]]; then
  PUSH_FLAG="--push"
  echo "Push flag enabled: The image will be pushed after the build."
else
  PUSH_FLAG=""
  echo "Push flag disabled: The image will not be pushed after the build."
fi

######################################
# Start Multi-Arch Build Process
######################################
echo "Starting multi-arch build..."

# Update PHP version in composer.json using the environment variable.
echo "Updating PHP version in composer.json to ${PHP_VERSION}..."
sed -i "s/\"php\": \"[^\"]*\"/\"php\": \"${PHP_VERSION}\"/" composer.json

######################################
# Debug: Print Build Arguments
######################################
echo "💡 Debugging Build Arguments Before Build:"
echo "PHP_VERSION=${PHP_VERSION}"
echo "IP_SOURCE=${IP_SOURCE}"
echo "IP_VERSION=${IP_VERSION}"
echo "IP_LANGUAGE=${IP_LANGUAGE}"
echo "IP_IMAGE=${IP_IMAGE}"
echo "PUID=${PUID}"
echo "PGID=${PGID}"

# Check if all required environment variables are set.
if [[ -z "$PHP_VERSION" || -z "$IP_SOURCE" || -z "$IP_VERSION" || -z "$IP_LANGUAGE" || -z "$IP_IMAGE" ]]; then
  echo "❌ ERROR: One or more required environment variables are missing!"
  exit 1
fi

######################################
# Authentication Reminder for Docker Push
######################################
echo "Reminder: Ensure you are logged into Docker Hub and GHCR before pushing."
echo "For Docker Hub: docker login"
echo "For GHCR: echo \$GHCR_TOKEN | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin"

######################################
# Clean Up and Setup QEMU Emulation
######################################
echo "Removing cached multiarch/qemu-user-static:latest image (if exists)..."
docker image rm multiarch/qemu-user-static:latest || echo "No cached image to remove."

echo "Registering QEMU emulation using tonistiigi/binfmt..."
docker run --rm --privileged tonistiigi/binfmt --install all

######################################
# Setup Docker Buildx Builder
######################################
# Determine which Buildx command is available.
if command -v docker-buildx >/dev/null 2>&1; then
  DOCKER_BUILDX=(docker-buildx)
else
  DOCKER_BUILDX=(docker buildx)
fi

# Check if a multiarch-builder already exists; reuse it if so.
if "${DOCKER_BUILDX[@]}" ls | grep -q "multiarch-builder"; then
  echo "Using existing multiarch-builder..."
  "${DOCKER_BUILDX[@]}" use multiarch-builder
else
  echo "Creating multiarch-builder..."
  "${DOCKER_BUILDX[@]}" create --driver docker-container --use --name multiarch-builder
  "${DOCKER_BUILDX[@]}" inspect --bootstrap
fi

######################################
# Build (and Optionally Push) the Multi-Arch Image
######################################
echo "Building multi-arch image for platforms linux/amd64 and linux/arm64..."
"${DOCKER_BUILDX[@]}" build --no-cache --progress=plain \
  --platform linux/amd64,linux/arm64 \
  --build-arg PHP_VERSION="${PHP_VERSION}" \
  --build-arg IP_LANGUAGE="${IP_LANGUAGE}" \
  --build-arg IP_VERSION="${IP_VERSION}" \
  --build-arg IP_SOURCE="${IP_SOURCE}" \
  --build-arg IP_IMAGE="${IP_IMAGE}" \
  --build-arg PUID="${PUID}" \
  --build-arg PGID="${PGID}" \
  -t "${IP_IMAGE}:${IP_VERSION}" \
  -t "ghcr.io/${IP_IMAGE}:${IP_VERSION}" \
  ${PUSH_FLAG} \
  .

echo "Multi-arch Docker image build complete."
echo "PHP_VERSION: ${PHP_VERSION}"



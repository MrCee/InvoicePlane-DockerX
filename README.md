<div align="center">
  <img src="assets/logo.svg" alt="InvoicePlane Logo">
</div>

<p align="left">
  <img src="https://img.shields.io/badge/architecture-x86__64-blue.svg" alt="Architecture">
  <img src="https://img.shields.io/badge/architecture-ARM64-blue.svg" alt="Architecture">
</p>

# InvoicePlane DockerX

**InvoicePlane DockerX** offers a fully dockerized, up-to-date version of InvoicePlane, complete with the latest patches and dependencies. Enjoy a secure, reliable multi-architecture build with a simple one-click setup.

## Key Benefits

- **Multi-Architecture Support:**  
  Run seamlessly on x86_64 and ARM-based platforms, including Apple Silicon M1+.
- **Local Persistence & Customization:**  
  Your uploads, CSS, views, and language files remain intact on your host system, ensuring your customizations persist through updates.
- **Streamlined Deployment:**  
  Use Docker Compose and our kickstart script for hassle-free, one-click setup.
- **Enhanced Compatibility:**  
  Optimized for a smooth experience with PHP 8.4, MariaDB 10.6, the latest patches from the community, and Nginx.

## Volume Mapping & Data Persistence

To ensure persistent data and seamless integration, the following host directories are bind-mounted into the container:

- **`./invoiceplane_uploads` → `/var/www/html/uploads`**  
  Files uploaded via the InvoicePlane interface are stored here.

- **`./invoiceplane_css` → `/var/www/html/assets/core/css`**  
  Custom CSS files or modifications to the core styles are maintained here.

- **`./invoiceplane_views` → `/var/www/html/application/views`**  
  The application's view templates are available from this directory.

- **`./invoiceplane_language` → `/var/www/html/application/language/${IP_LANGUAGE}`**  
  Language-specific files for InvoicePlane are loaded from this folder.

- **`./mariadb` → `/var/lib/mysql`**  
  The persistent data for the MariaDB container is stored here.

**Additional Key Points:**

- **Host Persistence:**  
  These directories remain on your host machine rather than being managed as transient Docker volumes. This ensures that content is never overwritten during updates or lost when containers are stopped or removed.

- **Selective Population:**  
  Data is populated only if the mount points are empty—similar to how MariaDB handles its data—so your existing content is always preserved.

- **Custom Language Preservation:**  
  Your custom language files are always preserved, ensuring that any modifications you make remain intact regardless of updates.

## 1. Clone the Repository

```bash
git clone https://github.com/MrCee/InvoicePlane-DockerX.git
```

### Repository Structure

```
InvoicePlane-DockerX
├── assets
│   └── logo.svg
├── composer.json
├── composer.lock
├── dev
│   ├── dev-build.sh
│   └── dev-docker-compose.build.yml
├── docker-compose.yml
├── Dockerfile
├── kickstart.sh
├── patches
│   ├── 0001-CodeIgniter3-php-8.4-ready-and-maintened-by-pocketar.patch
│   └── 0002-Fix-php-8.4-Deprecated-E_STRICT.patch
├── README.md
└── setup
    ├── nginx.conf
    ├── php-fpm.conf
    ├── php.ini
    ├── start.sh
    └── wait-for-db.sh
```

## 2. Set the Environment

Copy the provided `.env.example` to `.env` and adjust the values to suit your local or production environment. The `docker-compose.yml` file and other repository components will pull in these variables.

```bash
cp .env.example .env
```

## 3. One-click deployment using Kickstart

Run the kickstart script to create all necessary directories and deploy both the InvoicePlane and MariaDB containers. If all of the environment variables are correctly set, this one-click setup should get you up and running quickly.

```
./kickstart.sh
```

Host directories are created for mountpoints within the folder and populated with further files and directories:

```
InvoicePlane-DockerX
├── invoiceplane_css
├── invoiceplane_language
├── invoiceplane_uploads
├── invoiceplane_views
│   ├── emails
│   ├── errors
│   ├── invoice_templates
│   ├── quote_templates
│   └── reports
```

The InvoicePlane-DockerX and MariaDB will be pulled from Github and deployed using variables specifed in .env file.

## Other features

### Patches

All files contained within the `patches` directory will be automatically applied providing that filenames end with '.patch'.

### Language

Setting the IP_LANGUAGE variable in the .env file will determine what you see in the `./invoiceplane_language` directory on the host.<br><br>
Making a change to this variable and rebuilding the container will update main language files so they are accessable to you within this directory.<br><br>
We will always preserve the custom_lang.php file which should be the only file used for making changes across the system.<br><br>
Languages should be chosen carfully and reflect the exact directory captitalization structure.

<a href="https://www.buymeacoffee.com/MrCee" target="_blank">
    <img src="https://cdn.buymeacoffee.com/buttons/v2/default-violet.png" width="200">
</a>

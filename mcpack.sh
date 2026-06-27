#!/bin/bash
set -e

echo "Cloning installer repository..."
git clone https://github.com/rredefined/installer.git

echo "Moving installer contents to /var/www..."
mv installer/* /var/www/

echo "Changing to /var/www..."
cd /var/www

echo "Running MCPACK..."
php artisan mcpack:run

echo "Done!"

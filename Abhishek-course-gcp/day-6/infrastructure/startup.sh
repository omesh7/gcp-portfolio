#!/bin/bash
sudo apt-get update
sudo apt-get install -y nginx
echo "Welcome to Day-7 MIG Demo - $(hostname)" > /var/www/html/index.html
sudo systemctl start nginx
sudo systemctl enable nginx
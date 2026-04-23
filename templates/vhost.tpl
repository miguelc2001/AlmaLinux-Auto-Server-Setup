<VirtualHost *:80>
    ServerName   __DOMINIO__
    ServerAlias  www.__DOMINIO__
    DocumentRoot __DOCROOT__

    <Directory __DOCROOT__>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    ErrorLog  /var/log/httpd/__DOMINIO__-error.log
    CustomLog /var/log/httpd/__DOMINIO__-access.log combined
</VirtualHost>

# Usa a imagem base do PHP 8.3 com Apache
FROM php:8.3-apache

# Define variáveis de ambiente para instalações não interativas do apt-get
ENV DEBIAN_FRONTEND=noninteractive

# Instala dependências do sistema
# Agrupa os comandos apt-get para otimizar as camadas da imagem
# `--no-install-recommends` evita a instalação de pacotes não essenciais
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ffmpeg \
    libfreetype6-dev \
    libicu-dev \
    libgmp-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    libwebp-dev \
    libxpm-dev \
    libzip-dev \
    unzip \
    zlib1g-dev \
    # Limpa os caches do apt para reduzir o tamanho final da imagem
    && rm -rf /var/lib/apt/lists/*

# Configura extensões PHP
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-configure intl

# Instala extensões PHP
# Adicionado 'mbstring' explicitamente, que é crucial para muitas aplicações PHP
# e foi um ponto de atenção no seu log anterior.
# `-j$(nproc)` permite compilação paralela para acelerar o processo.
RUN docker-php-ext-install -j$(nproc) bcmath calendar exif gd gmp intl mbstring mysqli pdo pdo_mysql zip

# Instala Composer usando um estágio de build multi-stage
# Copia o binário do Composer de uma imagem oficial para garantir a versão correta
COPY --from=composer:2.7 /usr/bin/composer /usr/local/bin/composer

# Instala Node.js
# Isso adicionará Node.js globalmente na imagem. É útil para compilar assets (Laravel Mix/Vite).
# Se o 'laravel-echo-server' precisar rodar continuamente, considere um serviço separado
# ou uma configuração com Supervisord (que não está neste Dockerfile, mas pode ser adicionado).
COPY --from=node:22.9 /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=node:22.9 /usr/local/bin/node /usr/local/bin/node
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm

# Instala dependências globais do Node.js (se necessárias para o processo de build)
RUN npm install -g npx

# Define o diretório de trabalho padrão dentro do container
# Para `php:apache`, `/var/www/html` é o DocumentRoot padrão.
WORKDIR /var/www/html

# Copia o código da sua aplicação para o diretório de trabalho
# O Easypanel geralmente faz isso automaticamente.
COPY . /var/www/html

# Instala as dependências PHP com Composer
# Otimiza o autoloader e limpa os caches após a instalação.
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist --optimize-autoloader \
    && composer dump-autoload --optimize --classmap-authoritative \
    && php artisan optimize:clear # Limpa caches do Laravel

# Se a sua aplicação Krayin precisar compilar assets frontend (JavaScript/CSS):
# Descomente as linhas abaixo. Ex: Laravel Mix/Vite.
# RUN npm install
# RUN npm run build # Ou `npm run prod` dependendo do seu package.json

# Define as permissões para o usuário do servidor web (www-data)
# Essencial para que a aplicação Laravel possa escrever nos diretórios 'storage' e 'bootstrap/cache'.
# Permissões 755 para diretórios e 644 para arquivos é um bom padrão,
# com 775 para 'storage' e 'bootstrap/cache' para escrita pelo grupo.
RUN chown -R www-data:www-data /var/www/html \
    && find /var/www/html -type d -exec chmod 755 {} \; \
    && find /var/www/html -type f -exec chmod 644 {} \; \
    && chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache \
    && chmod -R 775 /var/www/html/storage \
    && chmod -R 775 /var/www/html/bootstrap/cache

# Configura o Apache
# Copia seu arquivo de configuração customizado do Apache.
# Certifique-se de que o arquivo `.configs/apache.conf` esteja no mesmo nível do Dockerfile no seu projeto.
# ESTE ARQUIVO DEVE DEFINIR O DocumentRoot CORRETAMENTE (ex: /var/www/html/public)
COPY ./.configs/apache.conf /etc/apache2/sites-available/000-default.conf
RUN a2enmod rewrite \
    && a2ensite 000-default.conf # Habilita o site configurado

# Expõe a porta 80, que é onde o Apache escuta por requisições HTTP
EXPOSE 80

# O comando padrão da imagem `php:apache` já inicia o Apache em foreground.
# Não é necessário um CMD customizado a menos que você queira sobrescrever esse comportamento.
# CMD ["apache2-foreground"] # (Implícito pela imagem base)
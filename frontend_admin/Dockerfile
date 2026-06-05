# Stage 1: Build the Flutter web app
FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app
ARG CACHE_BUST=1
RUN echo "Cache bust: $CACHE_BUST"
COPY . .
RUN flutter pub get
RUN dart run tools/update_version.dart
RUN flutter build web --release

# Stage 2: Serve with Nginx
FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
# Copia la configurazione Nginx globale che fa proxy pass a FastAPI
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]

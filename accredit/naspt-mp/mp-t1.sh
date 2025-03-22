docker run -itd \
  --name AMMDS \
  -p 8080:80 \
  -v /volume1/docker/ammds/data:/ammds/data \
  -v /volume1/docker/ammds/db:/ammds/db \
  -v /volume1/media/downloads:/ammds/download \
  -v /volume1/media/links:/media \
  --restart always \
  qyg2297248353/ammds:latest
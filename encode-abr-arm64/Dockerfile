FROM public.ecr.aws/lambda/ruby:2.7

COPY ../encode-abr/app.rb ./encode-abr/Gemfile ./encode-abr/encode.sh ./
COPY arm64/ffmpeg /opt/bin/
COPY arm64/ffprobe /opt/bin/

ENV GEM_HOME=${LAMBDA_TASK_ROOT}
RUN bundle install

# Command can be overwritten by providing a different command in the template directly.
CMD ["app.lambda_handler"]
FROM public.ecr.aws/lambda/ruby:2.7

COPY app.rb Gemfile encode.sh ./
COPY amd64/ffmpeg /opt/bin/
COPY amd64/ffprobe /opt/bin/

ENV GEM_HOME=${LAMBDA_TASK_ROOT}
RUN bundle install

# Command can be overwritten by providing a different command in the template directly.
CMD ["app.lambda_handler"]
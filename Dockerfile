ARG My_AWS_ACCOUNT=SOME_DEFAULT_IMAGE repo_name tag
FROM ${My_AWS_ACCOUNT}.dkr.ecr.ap-south-1.amazonaws.com/${repo_name}:${tag}
ENV PYTHONUNBUFFERED=1 \
    TZ=Asia/Calcutta
WORKDIR /app
RUN apt-get update \
  && apt-get install -y build-essential curl libpq-dev  --no-install-recommends \
  && apt-get install wkhtmltopdf -y \
  && rm -rf /var/lib/apt/lists/* /usr/share/doc /usr/share/man \
  && apt-get clean \
  && cp -rp /usr/bin/wkhtmltopdf /bin \
  && useradd --create-home python \
  && chown python:python -R /app  \
  && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime  \
  && echo $TZ > /etc/timezone
USER python
COPY --chown=python:python . .
RUN pip3 install --no-warn-script-location --user -r requirements.txt
ENV PATH="/home/python/.local/bin:${PATH}"
EXPOSE 5000

CMD [\
"gunicorn","main:app",\
"-c", "gunicorn.config.py",\
"--worker-class", "uvicorn.workers.UvicornWorker",\
"--bind", "0.0.0.0:5000",\
"--access-logfile", "-",\
"--graceful-timeout", "120",\ 
"--max-requests", "1000", \ 
"--max-requests-jitter", "50",\
"--preload"\
]

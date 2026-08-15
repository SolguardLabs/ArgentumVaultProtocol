FROM python:3.12-slim

WORKDIR /opt/argentum
COPY requirements.txt ./
RUN python -m pip install --no-cache-dir -r requirements.txt

COPY pyproject.toml pytest.ini ./
COPY src ./src
COPY client ./client
COPY tests ./tests

CMD ["python", "-m", "pytest", "-q"]

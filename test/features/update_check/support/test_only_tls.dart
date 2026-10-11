// TEST-ONLY TLS identity for the local HTTPS server in the SE-41 fetcher
// tests. Self-signed for localhost/127.0.0.1. It protects nothing and must
// never be used outside test/.

const String testOnlyLocalhostCertPem = '''
-----BEGIN CERTIFICATE-----
MIIBmzCCAUGgAwIBAgIUTpLjXPkfEGYOnxMhgHiJ1h9GKvUwCgYIKoZIzj0EAwIw
FDESMBAGA1UEAwwJbG9jYWxob3N0MCAXDTI2MTAxMDIyNDYzOVoYDzIxMjYwOTE2
MjI0NjM5WjAUMRIwEAYDVQQDDAlsb2NhbGhvc3QwWTATBgcqhkjOPQIBBggqhkjO
PQMBBwNCAATBvcqZx9wP9TDEJHe+DKb85Vbqjs8T6i2ACUdxpxKjxVrkOjpTKGvH
mmbH1fvE2953zpvSLUOrDvOCQdO1jy9co28wbTAdBgNVHQ4EFgQUC/MzkIdBqaco
UCwpAioA6JV55TAwHwYDVR0jBBgwFoAUC/MzkIdBqacoUCwpAioA6JV55TAwDwYD
VR0TAQH/BAUwAwEB/zAaBgNVHREEEzARgglsb2NhbGhvc3SHBH8AAAEwCgYIKoZI
zj0EAwIDSAAwRQIhAJcruP1xwwU0pYBdfC0pDaECjxTu0j2uOiitFGWdtAWAAiAj
k1nit8OegzFiJVM2n4g6Sycl3YeYDFnP3Q1oTqKiMQ==
-----END CERTIFICATE-----
''';

const String testOnlyLocalhostKeyPem = '''
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgL0Ka062RdefBELxa
cYhF2HIbyL6fi58PGU+QDdbIOT2hRANCAATBvcqZx9wP9TDEJHe+DKb85Vbqjs8T
6i2ACUdxpxKjxVrkOjpTKGvHmmbH1fvE2953zpvSLUOrDvOCQdO1jy9c
-----END PRIVATE KEY-----
''';

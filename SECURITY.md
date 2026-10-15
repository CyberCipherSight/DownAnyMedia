# Security

There is no supported release matrix or guaranteed security response time yet. Use current upstream engines and review dependency updates before distributing builds.

For sensitive findings, use GitHub's private vulnerability reporting feature if enabled on the repository. If it is unavailable, open an issue requesting a private reporting route without including exploit details, credentials, personal information, or affected private URLs. No personal contact address is published by this project.

The optional AES-GCM remote configuration key is recoverable from the client; it is not a server-authentication or authorization mechanism. No production key is included, no configuration endpoint is supplied by default, and the service is not connected to the current UI. See the remote configuration guide for its full limitations.

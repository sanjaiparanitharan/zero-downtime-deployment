
# Zero-Downtime Deployment and Rollback

## Project Overview

This project implements Blue-Green Deployment using Jenkins,
Docker, Nginx, Python Flask and AWS EC2.

## Application Versions

- Version 1: Blue environment
- Version 2: Green environment

## Technologies

- AWS EC2
- Ubuntu
- Jenkins
- Docker
- Python Flask
- Nginx
- GitHub

## Application Endpoints

- / : Application information
- /health : Application health check

## Deployment Strategy

1. Deploy Version 1.
2. Start Version 2 alongside Version 1.
3. Perform health checks.
4. Switch Nginx traffic to Version 2.
5. Roll back to Version 1 if deployment fails.

## Docker Images

- zero-downtime-app:v1
- zero-downtime-app:v2

## Application Ports

- Version 1: 5001
- Version 2: 5002
- Nginx: 80
- Jenkins: 8080

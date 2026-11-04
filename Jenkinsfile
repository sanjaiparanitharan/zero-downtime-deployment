
pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
        timeout(time: 15, unit: 'MINUTES')
    }

    stages {

        stage('Checkout') {
            steps {
                echo 'Checking out source code from GitHub'
                checkout scm

                sh '''
                    echo "Source code downloaded successfully"
                    ls -la
                '''
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    env.IMAGE_TAG = "build-${env.BUILD_NUMBER}"
                    env.APP_VERSION = "jenkins-${env.BUILD_NUMBER}"
                }

                sh '''
                    echo "Building Docker image..."
                    docker build \
                        -t zero-downtime-app:${IMAGE_TAG} \
                        -f app/Dockerfile app

                    echo "Docker image created:"
                    docker images zero-downtime-app
                '''
            }
        }

        
stage('Determine Deployment Target') {
    steps {
        script {
            def activePort = sh(
                script: '''
                    awk '/server 127.0.0.1:/ {
                        sub(/^.*:/, "", $2)
                        sub(/;/, "", $2)
                        print $2
                    }' /etc/nginx/conf.d/flask-upstream.conf
                ''',
                returnStdout: true
            ).trim()

            echo "Currently active port: ${activePort}"

            if (activePort == '5001') {
                env.TARGET_PORT = '5002'
                env.APP_COLOR = 'green'
            } else if (activePort == '5002') {
                env.TARGET_PORT = '5001'
                env.APP_COLOR = 'blue'
            } else {
                error("Unexpected active Nginx port: ${activePort}")
            }

            echo "New application version: ${env.APP_VERSION}"
            echo "Deployment target port: ${env.TARGET_PORT}"
            echo "Application color: ${env.APP_COLOR}"
        }
    }
}

         
 
        stage('Deploy Application') {
            steps {
                sh '''
                    echo "Starting zero-downtime deployment..."

                    sudo -n /bin/bash \
                        /opt/zero-downtime-deployment/deploy.sh \
                        "$IMAGE_TAG" \
                        "$APP_VERSION" \
                        "$APP_COLOR" \
                        "$TARGET_PORT"
                '''
            }
        }

        stage('Verify Deployment') {
            steps {
                sh '''
                    echo "Checking application through Nginx..."

                    curl -fsS http://127.0.0.1/ | python3 -c '
import json
import sys

data = json.load(sys.stdin)
expected = sys.argv[1]

if data.get("version") != expected:
    raise SystemExit(
        f"Deployment verification failed: expected {expected}, "
        f"received {data.get('version')}"
    )

print("Application version:", data["version"])
print("Environment:", data["environment"])
print("Deployment verification successful")
' "$APP_VERSION"

                    echo "Checking health endpoint..."
                    curl -fsS http://127.0.0.1/health
                    echo
                '''
            }
        }
    }

    post {
        success {
            echo 'ZERO-DOWNTIME DEPLOYMENT COMPLETED SUCCESSFULLY'
        }

        failure {
            echo 'DEPLOYMENT FAILED - CHECK CONSOLE OUTPUT'
        }

        always {
            echo 'Jenkins pipeline execution finished.'
        }
    }
}

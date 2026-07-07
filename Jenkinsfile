pipeline {
    agent any

    environment {
        IMAGE_NAME = "sample-nodejs"
        IMAGE_TAG  = "${env.BUILD_NUMBER}"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('SAST - Semgrep') {
            steps {
                sh """
                    docker run --rm \
                        -v \${WORKSPACE}:/src \
                        semgrep/semgrep semgrep scan \
                        --config=auto \
                        --severity=ERROR \
                        --error \
                        /src
                """
            }
        }

        stage('Build Docker Image') {
            steps {
                sh "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ."
            }
        }

        stage('Trivy Scan') {
            steps {
                sh """
                    trivy image \
                        --exit-code 1 \
                        --severity HIGH,CRITICAL \
                        --no-progress \
                        ${IMAGE_NAME}:${IMAGE_TAG}
                """
            }
        }
    }

    post {
        always {
            sh "docker rmi ${IMAGE_NAME}:${IMAGE_TAG} || true"
            cleanWs()
        }
        failure {
            echo 'PR pipeline failed — merge is blocked.'
        }
        success {
            echo 'All checks passed — PR is ready to merge.'
        }
    }
}

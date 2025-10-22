# HNG DevOps Stage 1 Project

This repository showcases my submission for the **HNG Internship DevOps Stage 1** project.

---

## Overview

This project demonstrates my ability to **design, containerize, automate, and deploy** a modern web application in a production-ready environment using **Docker** and **NGINX**.

It emphasizes essential DevOps practices such as **infrastructure automation**, **continuous deployment**, and **server configuration management**, all achieved through **Bash scripting** and containerization.

---

## Task Objectives

### **1. Application Containerization**
- Package a simple web application into a **Docker container** using a well-defined **Dockerfile**.  
- Configure the containerized application to run on a dedicated internal port (e.g., `8080`).

### **2. Automated Deployment (Docker)**
- Utilize **Docker Compose** or automation scripts to manage container build and deployment.  
- Streamline the entire deployment process into a **single automated workflow**, eliminating the need for manual build and run commands.  
- Implement update logic that gracefully stops outdated containers before launching new ones.

### **3. Reverse Proxy Configuration**
- Set up **NGINX** as a **reverse proxy** to route external traffic from **port 80 (HTTP)** to the internal container port.  
- Ensure the application is publicly accessible through the server’s IP address or domain name.

### **4. One-Command Automated Deployment**
- Develop a single executable **Bash script** that automates every stage of deployment:
  - Pull or update source code  
  - Build and run Docker containers  
  - Configure and reload NGINX  
  - Validate setup and handle cleanup operations  

---

## Project Goal

The primary goal of this task is to **showcase my ability to take an application from source code to production**, using efficient packaging, automation, and deployment strategies.  

The outcome ensures that the application can be accessed seamlessly via the server’s **public IP address or domain name** on **HTTP port 80**, mirroring real-world deployment standards.

---

## Technologies Used

| Tool / Technology | Purpose |
|--------------------|----------|
| **Docker** | Containerization of the application |
| **Docker Compose** | Multi-container orchestration and service management |
| **NGINX** | Reverse proxy configuration and HTTP traffic routing |
| **Bash Scripting** | Automation of deployment workflow |
| **Git & GitHub** | Version control and repository management |
| **Linux (Ubuntu)** | Remote server environment |

---

## Deployment Workflow

Below is the step-by-step process implemented in this project:

1. **Code Retrieval**  
   The deployment script pulls the latest application source code from the GitHub repository.

2. **Environment Preparation**  
   Installs and verifies required dependencies Docker, Docker Compose, and NGINX on the remote server.

3. **Container Build & Deployment**  
   Builds the Docker image, then runs the container automatically using Docker Compose or direct Docker commands.

4. **NGINX Configuration**  
   Dynamically sets up an NGINX reverse proxy to route requests from port 80 to the container’s internal port.

5. **Validation & Health Checks**  
   Confirms that:
   - Docker is active  
   - Containers are running correctly  
   - NGINX is routing traffic as expected  

6. **Logging & Error Handling**  
   Every stage of deployment logs its success or failure to a timestamped log file, ensuring transparency and troubleshooting ease.

7. **Idempotency & Cleanup**  
   The script can safely re-run without breaking existing setups.  
   It gracefully removes or updates old containers and configurations when necessary.

---

---

## My Experience

This project provided valuable hands-on experience in infrastructure automation through the HNG Internship (DevOps Track).

I designed and implemented a fully automated deployment system that integrates Docker, NGINX, and custom shell scripting achieving seamless, single-command automation for application deployment and updates.

Through this process, I strengthened my understanding of:

- **Continuous Deployment (CD)**  
- **Server Configuration and Management**  
- **Container Orchestration Basics**  
- **Real-world CI/CD Workflows**
# hng-devops-stage1

## Author

**Name:** Mathias Olah  
**Slack Username:** [@omats1](https://hng.tech/slack)  
**Track:** DevOps  
**GitHub:** [omats1](https://github.com/omats1)  
**Email:** [olahmathias@gmail.com](mailto:olahmathias@gmail.com)

---

# GradHire iOS — AI Resume Optimization & Job Matching App

GradHire is a full-stack AI-powered platform that helps new graduates optimize their resumes and discover relevant job opportunities. This repository contains the **SwiftUI iOS frontend**, which connects to a FastAPI backend and an OpenAI-powered resume intelligence engine.

The app allows users to upload a resume, receive AI-driven improvements tailored to a job role, and download a professionally optimized resume PDF.

---

## 🚀 Features

### Resume Upload & Validation

* Upload PDF resumes securely from device storage
* Network connectivity checks before upload
* Backend resume validation and parsing
* Error handling for invalid or oversized files

### AI Resume Optimization

* Extracts resume text and matches it against job descriptions
* Identifies missing skills
* Generates ATS keywords
* Rewrites and improves experience bullet points
* Displays optimization results in a structured UI

### Job Matching

* Fetches relevant job listings based on resume content
* Displays match scores
* Bookmark/save jobs locally
* Navigate to job application links

### Resume PDF Generation

* Downloads AI-optimized resume
* Generates shareable PDF
* Native iOS share sheet integration

### UI/UX

* Modern SwiftUI interface
* Loading skeletons and animations
* Clean navigation architecture
* Error and empty states handling

---

## 🏗 Architecture Overview

The app follows a modular SwiftUI architecture with clear separation of concerns:

```
Views → ViewModels/Managers → Services → Network Layer → Backend API
```

### Core Layers

#### Views

SwiftUI UI components responsible for rendering screens and handling user interaction.

Key views:

* `UploadResumeView` — Resume upload entry screen
* `JobListView` — AI-matched job listings
* `JobDetailView` — Individual job details
* `OptimizeResumeView` — Resume optimization results
* `SavedJobsView` — Bookmarked jobs

#### Managers

Global state managers injected via environment objects.

* `ResumeManager` — Stores uploaded resume file reference
* `BookmarkManager` — Manages saved jobs

#### Services

Business logic and networking abstraction.

* `APIService` — Handles resume optimization and download
* `JobAPIService` — Fetches job listings
* `NetworkMonitor` — Monitors connectivity

#### Models

Data structures shared across app layers.

* `Job` — Job listing model
* `ResumeOptimizationResponse` — AI optimization response schema

---

## 🔌 Backend Integration

The iOS app communicates with a FastAPI backend that provides:

* `/resume/upload` — Resume validation
* `/jobs/from-resume` — AI job matching
* `/resume/optimize` — Resume improvement JSON
* `/resume/download` — Optimized PDF generation

The backend uses:

* FastAPI
* OpenAI API
* PDF parsing (pdfplumber)
* ReportLab PDF generation

---

## 🧠 AI Optimization Pipeline

1. User uploads resume
2. Resume text extracted and validated
3. AI compares resume against job description
4. AI returns structured JSON:

   * Summary improvements
   * Missing skills
   * ATS keywords
   * Improved experience bullets
5. Frontend renders results
6. Backend generates optimized PDF

---

## 📁 Project Structure

```
GradHire
├── Views/
│   ├── UploadResumeView.swift
│   ├── JobListView.swift
│   ├── OptimizeResumeView.swift
│   └── ...
├── Managers/
│   ├── ResumeManager.swift
│   └── BookmarkManager.swift
├── Models/
│   ├── Job.swift
│   └── ResumeOptimizationResponse.swift
├── Services/
│   ├── APIService.swift
│   └── NetworkMonitor.swift
├── Network/
│   ├── APIConstants.swift
│   └── JobAPIService.swift
└── GradHireApp.swift
```

---

## 🛠 Tech Stack

### Frontend

* SwiftUI
* Combine
* URLSession networking
* Native iOS file handling
* MVVM-inspired architecture

### Backend (separate repo)

* FastAPI
* OpenAI API
* Python PDF processing

---

## ⚙️ Setup Instructions

### Requirements

* macOS
* Xcode 15+
* iOS Simulator or device

### Steps

1. Clone repository:

```
git clone git@github.com:prakhar0311/gradhire-ios.git
```

2. Open project:

```
open GradHire.xcodeproj
```

3. Run in Xcode simulator

4. Ensure backend server is running and API endpoints are configured in `APIConstants.swift`

---

## 🔒 Security Considerations

* No API keys stored in frontend
* Backend handles OpenAI requests
* Secure file handling for resumes
* Network connectivity validation

---

## 🎯 Roadmap

Planned improvements:

* Resume template system
* In-app resume preview
* Cover letter generation
* User accounts and cloud storage
* Enhanced job filtering
* Analytics dashboard

---

## 🤝 Contributing

Contributions are welcome.

Suggested areas:

* UI polish
* Resume templates
* Performance optimizations
* Accessibility improvements

---

## 📄 License

This project is for educational and portfolio purposes.

---

## 👤 Author

**Prakhar Ghirnikar**

AI-powered job tools for new graduates.

---

## ⭐ Final Notes

GradHire demonstrates:

* Full-stack AI product architecture
* Real-world iOS app development
* Backend API integration
* Resume optimization workflow
* Professional software engineering practices

This project is designed as a portfolio-ready production system showcasing applied AI in career tools.

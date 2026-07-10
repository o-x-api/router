# Contributing to GH_OmniRout

Thank you for your interest in contributing to **GH_OmniRout**! We welcome contributions of all forms, including bug reports, feature requests, documentation improvements, and code submissions.

---

## 🛠️ How to Contribute

### 1. Reporting Bugs & Feature Requests
* **Search Existing Issues:** Before opening a new issue, check the issues tab to see if it has already been reported.
* **Be Specific:** Provide as much detail as possible, including environment logs, reproduction steps, expected behavior, and screenshot evidence if applicable.

### 2. Submitting Pull Requests
1. **Fork the Repository:** Create a personal copy of the repository on GitHub.
2. **Create a Feature Branch:** Build your branch off the `main` branch. Use a descriptive name (e.g., `feature/backup-compress` or `fix/heartbeat-offset`).
3. **Commit your Changes:** Write clear, concise commit messages.
4. **Push and PR:** Push the branch to your fork and submit a Pull Request targeting the `main` branch of this repository.

---

## 🧑‍💻 Code Style & Standards

* **Keep Shell Scripts Clean:** Use `set -euo pipefail` inside all bash scripts. Check syntax and formatting before committing.
* **Test Locally:** Verify that any changes to `entrypoint.sh` or `start.sh` build correctly in a local Docker test sandbox if possible.
* **Maintain Clean Logs:** Do not leave trailing or verbose debug statements in production scripts.

---

## ⚖️ License
By contributing to this project, you agree that your contributions will be licensed under the project's **MIT License**.

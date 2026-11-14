# SC2026 GameDay - Marking & Scoring System

## 📋 Files Overview

### 1. **SC2026_Marking_Scheme.xlsx** ⭐
Single unified marking scheme covering **both Day 1 & Day 2**

- **Day 1 Section** (50 marks): Complaint Processing Pipeline
  - Operational Excellence: 10 marks
  - Security: 10 marks
  - Reliability: 10 marks
  - Performance Efficiency: 10 marks
  - Cost Optimization: 10 marks

- **Day 2 Section** (50 marks): E-Commerce Platform
  - Same 5 AWS pillars: 10 marks each

- **Total**: 100 marks
- **Format**: WorldSkills professional template style
- **Features**: Auto-calculated totals, color-coded sections, evaluator status column

### 2. **score_day1.sh**
Automated validator & scorer for Day 1 deployment

```bash
./score_day1.sh
```

### 3. **score_day2.sh**
Automated validator & scorer for Day 2 deployment

```bash
./score_day2.sh
```

---

## 🚀 Quick Start

### Setup
```bash
chmod +x score_day*.sh
aws sts get-caller-identity  # Verify AWS access
```

### Score a Team
```bash
# Open marking scheme
open SC2026_Marking_Scheme.xlsx

# Day 1 validation
./score_day1.sh > day1_results.txt

# Day 2 validation  
./score_day2.sh > day2_results.txt

# Use results to fill XLSX
# System auto-calculates totals
```

### With AWS Profile
```bash
AWS_PROFILE=learner-lab ./score_day1.sh
AWS_PROFILE=learner-lab ./score_day2.sh
```

---

## 📊 Scoring

- **≥ 70 marks**: PASS ✅ (exit code 0)
- **< 70 marks**: FAIL ❌ (exit code 1)

---

## 📚 Full Guide

See `MARKING_GUIDE.md` for complete documentation.

---

**SC2026 GameDay**  
*Single marking scheme + Two automated scoring scripts*  
*Ready for competition use*

import os
import pptx
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN
from pptx.enum.shapes import MSO_SHAPE

# Initialize presentation
prs = Presentation()
prs.slide_width = Inches(13.33)  # 16:9 Widescreen standard
prs.slide_height = Inches(7.5)

# Color Scheme Definition
COLOR_BG = RGBColor(15, 23, 42)       # Slate 900 #0F172A
COLOR_WHITE = RGBColor(255, 255, 255) # Pure White
COLOR_SILVER = RGBColor(148, 163, 184)# Slate 400 #94A3B8
COLOR_CARD = RGBColor(30, 41, 59)     # Slate 800 #1E293B

# Accent colors for pillars
COLOR_RED = RGBColor(239, 68, 68)     # Accent Crimson (Attack) #EF4444
COLOR_CYAN = RGBColor(6, 182, 212)    # Accent Teal (Diagnostics) #06B6D4
COLOR_GREEN = RGBColor(34, 197, 94)   # Accent Green (Mitigation) #22C55E
COLOR_YELLOW = RGBColor(234, 179, 8)  # Accent Yellow #EAB308

# Helper function to set slide background
def set_dark_bg(slide):
    background = slide.background
    fill = background.fill
    fill.solid()
    fill.fore_color.rgb = COLOR_BG

# Helper function to create title section on content slides
def add_slide_header(slide, title_text, category="HEXA FORCE CONTAINER SECURITY"):
    # Add a thin cyan category label
    cat_box = slide.shapes.add_textbox(Inches(0.8), Inches(0.4), Inches(11.7), Inches(0.3))
    tf_cat = cat_box.text_frame
    tf_cat.word_wrap = True
    tf_cat.margin_left = tf_cat.margin_right = tf_cat.margin_top = tf_cat.margin_bottom = 0
    p_cat = tf_cat.paragraphs[0]
    p_cat.text = category.upper()
    p_cat.font.name = "Trebuchet MS"
    p_cat.font.size = Pt(10)
    p_cat.font.bold = True
    p_cat.font.color.rgb = COLOR_CYAN
    
    # Add the main title
    title_box = slide.shapes.add_textbox(Inches(0.8), Inches(0.6), Inches(11.7), Inches(0.8))
    tf_title = title_box.text_frame
    tf_title.word_wrap = True
    tf_title.margin_left = tf_title.margin_right = tf_title.margin_top = tf_title.margin_bottom = 0
    p_title = tf_title.paragraphs[0]
    p_title.text = title_text
    p_title.font.name = "Trebuchet MS"
    p_title.font.size = Pt(26)
    p_title.font.bold = True
    p_title.font.color.rgb = COLOR_WHITE

# Helper to create bullet points in a modern look
def add_bullet_points(slide, left, top, width, height, points):
    box = slide.shapes.add_textbox(left, top, width, height)
    tf = box.text_frame
    tf.word_wrap = True
    tf.margin_left = tf.margin_right = tf.margin_top = tf.margin_bottom = 0
    
    for i, pt in enumerate(points):
        p = tf.add_paragraph() if i > 0 else tf.paragraphs[0]
        p.space_after = Pt(10)
        
        # Check special prefixes
        if pt.startswith("  - "):
            p.text = "   •  " + pt[4:]
            p.font.name = "Calibri"
            p.font.size = Pt(14)
            p.font.color.rgb = COLOR_SILVER
        elif pt.startswith("[CRITICAL]"):
            p.text = pt.replace("[CRITICAL]", "🔴 ")
            p.font.name = "Calibri"
            p.font.size = Pt(15)
            p.font.bold = True
            p.font.color.rgb = COLOR_RED
        elif pt.startswith("[DIAGNOSTIC]"):
            p.text = pt.replace("[DIAGNOSTIC]", "🔵 ")
            p.font.name = "Calibri"
            p.font.size = Pt(15)
            p.font.bold = True
            p.font.color.rgb = COLOR_CYAN
        elif pt.startswith("[DEFENDED]"):
            p.text = pt.replace("[DEFENDED]", "🟢 ")
            p.font.name = "Calibri"
            p.font.size = Pt(15)
            p.font.bold = True
            p.font.color.rgb = COLOR_GREEN
        else:
            p.text = "•  " + pt
            p.font.name = "Calibri"
            p.font.size = Pt(15)
            p.font.bold = True
            p.font.color.rgb = COLOR_WHITE
            
    return box

# Helper to draw a stylized code box
def add_code_box(slide, left, top, width, height, lines):
    # Add background card for code
    card = slide.shapes.add_shape(
        MSO_SHAPE.RECTANGLE, left, top, width, height
    )
    card.fill.solid()
    card.fill.fore_color.rgb = COLOR_CARD
    card.line.color.rgb = COLOR_CYAN
    card.line.width = Pt(1)
    
    tf = card.text_frame
    tf.word_wrap = True
    tf.margin_left = Inches(0.2)
    tf.margin_right = Inches(0.2)
    tf.margin_top = Inches(0.15)
    tf.margin_bottom = Inches(0.15)
    
    for i, line in enumerate(lines):
        p = tf.add_paragraph() if i > 0 else tf.paragraphs[0]
        p.space_after = Pt(2)
        p.text = line
        p.font.name = "Consolas"
        p.font.size = Pt(10)
        p.font.color.rgb = COLOR_WHITE
        p.alignment = PP_ALIGN.LEFT
        
        # Simple color syntax highlights
        if "docker run" in line or "docker build" in line:
            p.font.color.rgb = COLOR_CYAN
        elif "--stage-" in line or "--all" in line:
            p.font.color.rgb = COLOR_GREEN
        elif "victim" in line:
            p.font.color.rgb = COLOR_YELLOW
            
    return card

# Helper to draw visual info cards
def add_info_card(slide, left, top, width, height, title, subtitle, content, border_color):
    card = slide.shapes.add_shape(
        MSO_SHAPE.RECTANGLE, left, top, width, height
    )
    card.fill.solid()
    card.fill.fore_color.rgb = COLOR_CARD
    card.line.color.rgb = border_color
    card.line.width = Pt(1.5)
    
    tf = card.text_frame
    tf.word_wrap = True
    tf.margin_left = Inches(0.2)
    tf.margin_right = Inches(0.2)
    tf.margin_top = Inches(0.2)
    tf.margin_bottom = Inches(0.2)
    
    # Title
    p_title = tf.paragraphs[0]
    p_title.text = title.upper()
    p_title.font.name = "Trebuchet MS"
    p_title.font.size = Pt(14)
    p_title.font.bold = True
    p_title.font.color.rgb = COLOR_WHITE
    p_title.space_after = Pt(4)
    
    # Subtitle
    if subtitle:
        p_sub = tf.add_paragraph()
        p_sub.text = subtitle
        p_sub.font.name = "Calibri"
        p_sub.font.size = Pt(11)
        p_sub.font.bold = True
        p_sub.font.color.rgb = border_color
        p_sub.space_after = Pt(8)
        
    # Content
    for text_line in content:
        p_cont = tf.add_paragraph()
        p_cont.text = "• " + text_line
        p_cont.font.name = "Calibri"
        p_cont.font.size = Pt(12)
        p_cont.font.color.rgb = COLOR_SILVER
        p_cont.space_after = Pt(4)

# ==========================================
# SLIDE 1: Title Slide
# ==========================================
slide_layout = prs.slide_layouts[6]
slide = prs.slides.add_slide(slide_layout)
set_dark_bg(slide)

title_box = slide.shapes.add_textbox(Inches(0.8), Inches(2.0), Inches(11.7), Inches(3.5))
tf = title_box.text_frame
tf.word_wrap = True

p1 = tf.paragraphs[0]
p1.text = "HEXA FORCE CONTAINER LAB"
p1.font.name = "Trebuchet MS"
p1.font.size = Pt(54)
p1.font.bold = True
p1.font.color.rgb = COLOR_CYAN
p1.space_after = Pt(4)

p2 = tf.add_paragraph()
p2.text = "4-Stage DevSecOps Attack & Mitigation Laboratory"
p2.font.name = "Trebuchet MS"
p2.font.size = Pt(26)
p2.font.color.rgb = COLOR_WHITE
p2.space_after = Pt(14)

p3 = tf.add_paragraph()
p3.text = "Hands-on Demonstration of Host Kernel Isolation, Capability Sets, Daemon Security, and Volume Bounds"
p3.font.name = "Calibri"
p3.font.size = Pt(13)
p3.font.italic = True
p3.font.color.rgb = COLOR_SILVER

# Metadata bottom
meta_box = slide.shapes.add_textbox(Inches(0.8), Inches(6.0), Inches(11.7), Inches(0.8))
tf_meta = meta_box.text_frame
p_meta = tf_meta.paragraphs[0]
p_meta.text = "PIPELINE ORCHESTRATION & LAB MANUAL  |  INTEGRATION BRIEFING"
p_meta.font.name = "Trebuchet MS"
p_meta.font.size = Pt(11)
p_meta.font.bold = True
p_meta.font.color.rgb = COLOR_SILVER

# ==========================================
# SLIDE 2: Agenda
# ==========================================
slide = prs.slides.add_slide(slide_layout)
set_dark_bg(slide)
add_slide_header(slide, "Briefing & Laboratory Agenda", "EXECUTIVE PRESENTATION GUIDE")

add_bullet_points(slide, Inches(0.8), Inches(1.8), Inches(5.5), Inches(4.8), [
    "01. The 4 Security Pillars Overview",
    "  - Key definitions, threat structures, and container security scope.",
    "02. Stage 1: Host Kernel Isolation",
    "  - Dirty COW (CVE-2016-5195) C exploit simulation and outcomes.",
    "03. Stage 2: Process & Capabilities Isolation",
    "  - Shared PID namespace boundaries and evaluation of CAP_SYS_PTRACE.",
    "04. Stage 3: Daemon & API Security",
    "  - Mitigating exposed docker.sock socket API mounts."
])

add_bullet_points(slide, Inches(6.8), Inches(1.8), Inches(5.7), Inches(4.8), [
    "05. Stage 4: Volume & Filesystem Security",
    "  - Writable host mount points and path traversal cron injection.",
    "06. GitHub Actions CI/CD Integration",
    "  - Validated dirtycow-lab.yml and automated execution steps.",
    "07. DevSecOps Hardening Checklist",
    "  - Hands-on rules to protect and secure container workloads.",
    "08. Hexa Force Conclusion",
    "  - Key lessons, takeaways, and final architecture summaries."
])

# ==========================================
# SLIDE 3: The 4 Security Pillars
# ==========================================
slide = prs.slides.add_slide(slide_layout)
set_dark_bg(slide)
add_slide_header(slide, "The 4 Security Pillars of Containers", "LABORATORY SCOPE")

# 4 Columns side-by-side representing the 4 pillars
card_w = Inches(2.7)
card_h = Inches(4.8)

add_info_card(
    slide, Inches(0.8), Inches(1.8), card_w, card_h,
    "1. Host Kernel", "Isolation Boundary",
    [
        "Containers share host OS kernel resources.",
        "Race condition exploits (e.g. Dirty COW) bypass all virtual restrictions.",
        "Demonstrates kernel memory isolation limits."
    ],
    COLOR_RED
)

add_info_card(
    slide, Inches(3.8), Inches(1.8), card_w, card_h,
    "2. Capabilities", "Process Boundaries",
    [
        "Process namespace mapping regulates visibility.",
        "Over-privileged debug access (CAP_SYS_PTRACE) allows host code injection.",
        "Demonstrates process capability containment."
    ],
    COLOR_CYAN
)

add_info_card(
    slide, Inches(6.8), Inches(1.8), card_w, card_h,
    "3. Engine API", "Daemon Protection",
    [
        "Mounting docker.sock grants host root access.",
        "Attacker controls engine and launches sibling mounts.",
        "Demonstrates socket boundary control."
    ],
    COLOR_YELLOW
)

add_info_card(
    slide, Inches(9.8), Inches(1.8), card_w, card_h,
    "4. Volume", "Filesystem Isolation",
    [
        "Writable mounts allow local file traversal.",
        "Exploit writes root task files to host cron.",
        "Demonstrates mount point security rule options."
    ],
    COLOR_GREEN
)

# ==========================================
# SLIDE 4: Stage 1 - Host Kernel Isolation
# ==========================================
slide = prs.slides.add_slide(slide_layout)
set_dark_bg(slide)
add_slide_header(slide, "Stage 1: Host Kernel Isolation (Dirty COW)", "STAGE 1 WORKFLOW")

add_bullet_points(slide, Inches(0.8), Inches(1.8), Inches(6.0), Inches(5.0), [
    "Exploit Concept (CVE-2016-5195)",
    "  - A kernel-level race condition in Linux's Copy-on-Write subsystem.",
    "  - Allows unprivileged user space writes to overwrite read-only cache pages.",
    "[CRITICAL] Exploit Execution",
    "  - The low-privilege container user compiles and runs dirtyc0w.c.",
    "  - Targets a read-only root file: /var/secret/target.txt.",
    "[DEFENDED] Automated Protection",
    "  - On modern kernels (like the host actions runner), the race fails.",
    "  - Write serialization holds page table blocks safely (Exploit Prevented)."
])

add_info_card(
    slide, Inches(7.2), Inches(1.8), Inches(5.3), Inches(4.8),
    "Detection & Mitigation Blueprint", "Hexa Force Remediation",
    [
        "Detection: Static scan container kernels for CVE-2016-5195 signatures.",
        "Detection: Audit syscall sequences using seccomp/madvise logs.",
        "Mitigation: Keep the underlying host OS kernel fully patched.",
        "Mitigation: Implement user-space container engines like gVisor or Kata Containers to intercept host syscalls."
    ],
    COLOR_RED
)

# ==========================================
# SLIDE 5: Stage 2 - Process & Capabilities Isolation
# ==========================================
slide = prs.slides.add_slide(slide_layout)
set_dark_bg(slide)
add_slide_header(slide, "Stage 2: Process & Capabilities Isolation", "STAGE 2 WORKFLOW")

add_bullet_points(slide, Inches(0.8), Inches(1.8), Inches(6.0), Inches(5.0), [
    "Exploit Concept (CAP_SYS_PTRACE)",
    "  - Over-privileged capabilities allow processes to read/write memory.",
    "  - Combined with shared host namespace, it allows full host injection.",
    "[DIAGNOSTIC] Capability Diagnostics",
    "  - Checks permissions using the 'capsh --print' utility.",
    "  - Runs namespace visibility tests using active PID checks.",
    "[DEFENDED] Namespace Isolation",
    "  - With standard isolated namespaces, host process listings are blocked.",
    "  - Ensures container tasks are isolated from host-level activities."
])

add_info_card(
    slide, Inches(7.2), Inches(1.8), Inches(5.3), Inches(4.8),
    "Detection & Mitigation Blueprint", "Hexa Force Remediation",
    [
        "Detection: Static configuration checks for --pid=host flags.",
        "Detection: Monitor runtime capabilities block registers for CAP_SYS_PTRACE.",
        "Mitigation: Never employ host PID integration flags.",
        "Mitigation: Configure policies to drop default capabilities: --cap-drop=ALL."
    ],
    COLOR_CYAN
)

# ==========================================
# SLIDE 6: Stage 3 - Daemon & API Security
# ==========================================
slide = prs.slides.add_slide(slide_layout)
set_dark_bg(slide)
add_slide_header(slide, "Stage 3: Daemon & API Security (docker.sock)", "STAGE 3 WORKFLOW")

add_bullet_points(slide, Inches(0.8), Inches(1.8), Inches(6.0), Inches(5.0), [
    "Exploit Concept (UNIX Socket Mount)",
    "  - The host daemon runs with full administrative privileges.",
    "  - Exposing docker.sock gives the guest system absolute daemon access.",
    "[CRITICAL] Hijack Simulation",
    "  - Detects exposed sockets and constructs direct REST API payloads.",
    "  - Models spawning sibling containers with host root mounted on /host.",
    "[DEFENDED] Control Mitigation",
    "  - The orchestrator verifies that without the socket file exposed,",
    "  - API requests are blocked, leaving guest system access closed."
])

add_info_card(
    slide, Inches(7.2), Inches(1.8), Inches(5.3), Inches(4.8),
    "Detection & Mitigation Blueprint", "Hexa Force Remediation",
    [
        "Detection: Track volume configuration definitions containing docker.sock.",
        "Detection: Run runtime monitoring (e.g. Falco) to flag HTTP curl operations against socket files.",
        "Mitigation: Prohibit socket integration mounts.",
        "Mitigation: Move workloads to secure Rootless engines (e.g. Podman)."
    ],
    COLOR_YELLOW
)

# ==========================================
# SLIDE 7: Stage 4 - Volume & Filesystem Security
# ==========================================
slide = prs.slides.add_slide(slide_layout)
set_dark_bg(slide)
add_slide_header(slide, "Stage 4: Volume & Filesystem Security", "STAGE 4 WORKFLOW")

add_bullet_points(slide, Inches(0.8), Inches(1.8), Inches(6.0), Inches(5.0), [
    "Exploit Concept (Path Traversal Mounts)",
    "  - Mounting host directories can provide write access to guest users.",
    "  - Attacker injects system-level scheduled jobs into root path folders.",
    "[CRITICAL] Cron Job Injection",
    "  - Simulates attempts to write task scripts inside /mnt/host/etc/cron.d.",
    "  - If successful, host triggers an arbitrary reverse shell task as root.",
    "[DEFENDED] Read-Only Volume Configuration",
    "  - Mount folder is owned by root with write privileges blocked.",
    "  - Write attempt is rejected with clean 'Permission Denied' outputs."
])

add_info_card(
    slide, Inches(7.2), Inches(1.8), Inches(5.3), Inches(4.8),
    "Detection & Mitigation Blueprint", "Hexa Force Remediation",
    [
        "Detection: Configure File Integrity Monitoring (FIM) on /etc/cron* folders.",
        "Detection: Audit file modification commands using standard host logging (auditd).",
        "Mitigation: Mount host volume integrations strictly as read-only (:ro).",
        "Mitigation: Prohibit directory mounts from critical host roots (/etc, /root, /var)."
    ],
    COLOR_GREEN
)

# ==========================================
# SLIDE 8: CI/CD Pipeline Automation
# ==========================================
slide = prs.slides.add_slide(slide_layout)
set_dark_bg(slide)
add_slide_header(slide, "Automated CI/CD Laboratory Pipeline", "PIPELINE ORCHESTRATION")

add_bullet_points(slide, Inches(0.8), Inches(1.8), Inches(6.0), Inches(5.0), [
    "CI/CD Integration Model",
    "  - Fully integrated using GitHub Actions workflow orchestration.",
    "  - Automatically builds and runs stages on every repository commit.",
    "[HIGHLIGHT] Hardware-Independent Verification",
    "  - The lab executes all stages directly on the host actions runner.",
    "  - Safely simulates exploits using unprivileged user accounts.",
    "Fast Execution Loop",
    "  - Optimizations reduce execution duration to under 40 seconds.",
    "  - Provides instant DevSecOps regression security assessment feedback."
])

add_code_box(slide, Inches(7.2), Inches(1.8), Inches(5.3), Inches(4.8), [
    "name: Dirty COW Lab CI Pipeline",
    "jobs:",
    "  build-and-run:",
    "    runs-on: ubuntu-latest",
    "    steps:",
    "    - name: Checkout Repository",
    "      uses: actions/checkout@v4",
    "      with:",
    "        token: ${{ secrets.GH_PAT }}",
    "",
    "    - name: Build Docker Container",
    "      run: docker build -t dirtycow-lab .",
    "",
    "    - name: Run Stage 1 (Host Kernel)",
    "      run: docker run --rm dirtycow-lab ... --stage-1",
    "",
    "    - name: Run Stage 2 (Capabilities)",
    "      run: docker run --rm dirtycow-lab ... --stage-2",
    "",
    "    - name: Run Stage 3 (API Daemon)",
    "      run: docker run --rm dirtycow-lab ... --stage-3",
    "",
    "    - name: Run Stage 4 (Volume Path)",
    "      run: docker run --rm dirtycow-lab ... --stage-4"
])

# ==========================================
# SLIDE 9: DevSecOps Hardening Rules
# ==========================================
slide = prs.slides.add_slide(slide_layout)
set_dark_bg(slide)
add_slide_header(slide, "DevSecOps Hardening & Defense-in-Depth", "BEST PRACTICES GUIDE")

# Three horizontal cards
add_info_card(
    slide, Inches(0.8), Inches(1.8), Inches(3.6), Inches(4.8),
    "1. Host Controls", "Kernel Security Level",
    [
        "Apply host kernel updates immediately to resolve CVE-2016-5195.",
        "Implement seccomp security rules.",
        "Employ sandbox container engines (gVisor) in untrusted public environments."
    ],
    COLOR_RED
)

add_info_card(
    slide, Inches(4.8), Inches(1.8), Inches(3.6), Inches(4.8),
    "2. Container Configuration", "Least Privilege Isolation",
    [
        "Never employ --pid=host namespaces.",
        "Drop all default privileges: docker run --cap-drop=ALL.",
        "Run services as custom USER victim (unprivileged accounts)."
    ],
    COLOR_CYAN
)

add_info_card(
    slide, Inches(8.8), Inches(1.8), Inches(3.6), Inches(4.8),
    "3. Storage & Storage APIs", "Access Controls",
    [
        "Enforce read-only volumes strictly using the :ro flag.",
        "Prohibit mounting /var/run/docker.sock UNIX sockets.",
        "Avoid mounting critical host configurations (/etc, /opt, /root)."
    ],
    COLOR_GREEN
)

# ==========================================
# SLIDE 10: Conclusion & Key Takeaways
# ==========================================
slide = prs.slides.add_slide(slide_layout)
set_dark_bg(slide)
add_slide_header(slide, "Conclusion: Hexa Force Lab Debriefing", "KEY TAKEAWAYS")

add_bullet_points(slide, Inches(0.8), Inches(1.8), Inches(6.0), Inches(5.0), [
    "Containers Share Host OS Foundations",
    "  - Container containment is only as strong as the host kernel.",
    "  - Bypassing kernel barriers compromises all namespaces.",
    "Mitigations are Multi-layered",
    "  - Securing pipelines requires host updates, capabilities control,",
    "  - socket restrictions, and read-only storage settings.",
    "[DEFENDED] Successful Hexa Force Outcome",
    "  - The CI/CD pipeline verified that modern kernels and proper",
    "  - read-only volume controls successfully contain advanced escapes.",
    "Continuous Security Regression Testing",
    "  - Integrating automated lab checks in GHA stops regressions before deploy."
])

add_info_card(
    slide, Inches(7.2), Inches(1.8), Inches(5.3), Inches(4.8),
    "The Golden Rule of DevSecOps", "Final Recommendation",
    [
        "Containers are NOT isolation virtual machines.",
        "Host OS updates are the baseline requirement for container cluster security.",
        "Drop capabilities, run as unprivileged users, mount volumes read-only, and audit docker.sock exposure constantly."
    ],
    COLOR_CYAN
)

# Save the presentation
output_path = "Hexa_Force_Lab_Presentation.pptx"
prs.save(output_path)
print(f"[+] Successfully generated widescreen 16:9 presentation at: {os.path.abspath(output_path)}")

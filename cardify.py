#!/usr/bin/env python3
import tkinter as tk
from tkinter import ttk, filedialog, messagebox, font
import markdown
import re
import os
import json
import shutil
import tempfile
from PIL import Image, ImageTk, ImageDraw
from reportlab.lib.pagesizes import inch
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
import io
import html
import sys
import threading
from datetime import datetime
import subprocess

class CardifyApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Cardify")
        self.root.geometry("1200x700")
        self.root.minsize(900, 600)
        
        # App icon
        if getattr(sys, 'frozen', False):
            # If the application is run as a bundle (packaged app)
            application_path = sys._MEIPASS
        else:
            # If running from script
            application_path = os.path.dirname(os.path.abspath(__file__))
            
        self.icon_path = os.path.join(application_path, "assets", "cardify_icon.png")
        try:
            icon = tk.PhotoImage(file=self.icon_path)
            self.root.iconphoto(True, icon)
        except:
            pass  # If icon not found, use default
        
        # Set default values
        self.content_font_size = 12
        self.title_font_size = 16
        self.tags_font_size = 10
        self.card_orientation = "portrait"  # portrait or landscape
        self.card_theme = "light"  # light or dark
        self.card_size = "3x5"  # 3x5, 4x6, etc.
        self.show_side_indicator = False  # Option to show/hide the side indicator
        
        # Front/back card support
        self.current_side = "front"  # front or back
        
        # Card collection
        self.cards = []
        self.current_card_index = 0
        
        # Create styles and theme
        self.create_styles()
        
        # Create a markdown example
        self.default_front = """# Sample Card

This is the front of a sample index card created with **Cardify**.

- Use markdown formatting
- Create beautiful cards
- Export to PDF
- Add content to both sides

Tags: #sample #cardify #markdown"""

        self.default_back = ""  # Empty default back
        
        # Setup UI
        self.setup_ui()
        
        # Initialize with default markdown for first card
        self.cards.append({
            "front": self.default_front, 
            "back": self.default_back,
            "title": "Sample Card"
        })
        self.markdown_text.insert("1.0", self.default_front)
        self.update_preview()
        self.update_card_counter()
        
        # Set up autosave
        self.autosave_timer = None
        self.setup_autosave()
        
        # Load settings
        self.load_settings()
        
    def load_settings(self):
        """Load application settings from config file"""
        config_path = self.get_config_path()
        if os.path.exists(config_path):
            try:
                with open(config_path, 'r') as f:
                    settings = json.load(f)
                    self.content_font_size = settings.get('content_font_size', 12)
                    self.title_font_size = settings.get('title_font_size', 16)
                    self.tags_font_size = settings.get('tags_font_size', 10)
                    self.card_theme = settings.get('card_theme', 'light')
                    self.card_orientation = settings.get('card_orientation', 'portrait')
                    self.card_size = settings.get('card_size', '3x5')
                    self.show_side_indicator = settings.get('show_side_indicator', False)
                    
                    # Update UI to match settings
                    self.update_preview()
                    
                    # Update orientation buttons
                    if self.card_orientation == "portrait":
                        self.portrait_btn.config(relief=tk.SUNKEN, bg=self.colors['button_active_bg'])
                        self.landscape_btn.config(relief=tk.RAISED, bg=self.colors['button_bg'])
                    else:
                        self.portrait_btn.config(relief=tk.RAISED, bg=self.colors['button_bg'])
                        self.landscape_btn.config(relief=tk.SUNKEN, bg=self.colors['button_active_bg'])
                        
            except Exception as e:
                print(f"Error loading settings: {e}")
    
    def save_settings(self):
        """Save application settings to config file"""
        config_dir = os.path.dirname(self.get_config_path())
        if not os.path.exists(config_dir):
            try:
                os.makedirs(config_dir, exist_ok=True)
            except Exception as e:
                print(f"Error creating config directory: {e}")
                # Fall back to Documents folder if needed
                if sys.platform == 'darwin':
                    config_dir = os.path.expanduser('~/Documents/Cardify')
                    os.makedirs(config_dir, exist_ok=True)
            
        settings = {
            'content_font_size': self.content_font_size,
            'title_font_size': self.title_font_size,
            'tags_font_size': self.tags_font_size,
            'card_theme': self.card_theme,
            'card_orientation': self.card_orientation,
            'card_size': self.card_size,
            'show_side_indicator': self.show_side_indicator
        }
        
        try:
            with open(self.get_config_path(), 'w') as f:
                json.dump(settings, f)
        except Exception as e:
            print(f"Error saving settings: {e}")
            messagebox.showwarning("Settings Warning", 
                                  "Could not save settings. Check folder permissions.")
    
    def get_config_path(self):
        """Get the path to the configuration file"""
        if sys.platform == 'darwin':  # macOS
            # Use Documents folder which is more likely to be writable
            config_dir = os.path.expanduser('~/Documents/Cardify')
        elif sys.platform == 'win32':  # Windows
            config_dir = os.path.join(os.environ['APPDATA'], 'Cardify')
        else:  # Linux and other Unix-like
            config_dir = os.path.expanduser('~/.config/cardify')
            
        return os.path.join(config_dir, 'config.json')
    
    def create_styles(self):
        """Create custom ttk styles for the application"""
        self.style = ttk.Style()
        
        # Configure the theme - use 'default' on macOS for better compatibility
        if sys.platform == "darwin":
            self.style.theme_use('default')
        else:
            self.style.theme_use('clam')
        
        # Define colors - optimized for better button visibility
        self.colors = {
            'bg': '#f5f5f7',
            'fg': '#333333',
            'accent': '#0033cc',         # Darker blue for better contrast
            'accent_dark': '#002280',    # Even darker blue for hover states
            'border': '#d1d1d6',
            'highlight': '#e6f2ff',
            'button_bg': '#d0d0d0',      # Light gray button background
            'button_fg': '#000000',      # BLACK text for maximum visibility
            'button_active_bg': '#b0b0b0', # Slightly darker when active
            'editor_bg': 'white',
            'preview_bg': 'white',
            'toolbar_bg': '#f5f5f7'
        }
        
        # Configure ttk styles
        self.style.configure('TFrame', background=self.colors['bg'])
        self.style.configure('TLabel', background=self.colors['bg'], foreground=self.colors['fg'])
        
        # Configure basic buttons - not using these as much, but configuring for completeness
        self.style.configure('TButton', 
                         background=self.colors['button_bg'], 
                         foreground=self.colors['button_fg'],
                         borderwidth=1)
        
        # Map dynamic states
        self.style.map('TButton',
                  background=[('active', self.colors['button_active_bg'])],
                  foreground=[('active', self.colors['button_fg'])])
        
        # Set special style for action buttons
        self.style.configure('Action.TButton', 
                         font=('Helvetica', 11, 'bold'),
                         background=self.colors['accent'],
                         foreground='white')
        
        self.style.map('Action.TButton',
                  background=[('active', self.colors['accent_dark'])],
                  foreground=[('active', 'white')])
        
        # Other styles
        self.style.configure('Card.TFrame', background=self.colors['preview_bg'], 
                            relief='solid', borderwidth=1)
        self.style.configure('Toolbar.TFrame', background=self.colors['toolbar_bg'])
        self.style.configure('Preview.TLabel', background=self.colors['preview_bg'], foreground=self.colors['fg'])
    
    def setup_ui(self):
        """Set up the main user interface"""
        # Main frame
        main_frame = ttk.Frame(self.root)
        main_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)
        
        # Top toolbar
        self.setup_toolbar(main_frame)
        
        # Card editor area
        self.editor_preview_frame = ttk.PanedWindow(main_frame, orient=tk.HORIZONTAL)
        self.editor_preview_frame.pack(fill=tk.BOTH, expand=True, pady=10)
        
        # Editor frame
        self.setup_editor()
        
        # Preview frame
        self.setup_preview()
        
        # Status bar
        self.setup_status_bar(main_frame)
        
        # Set up keyboard shortcuts
        self.setup_shortcuts()
    
    def setup_toolbar(self, parent):
        """Set up the application toolbar"""
        toolbar = ttk.Frame(parent, style='Toolbar.TFrame')
        toolbar.pack(fill=tk.X, padx=5, pady=5)
        
        # File operations section
        file_frame = ttk.Frame(toolbar, style='Toolbar.TFrame')
        file_frame.pack(side=tk.LEFT, padx=5)
        
        # New card button - with dark text on light background
        new_btn = tk.Button(file_frame, text="New Card", command=self.new_card,
                          bg=self.colors['button_bg'], 
                          fg=self.colors['button_fg'],
                          activebackground=self.colors['button_active_bg'],
                          activeforeground=self.colors['button_fg'],
                          highlightbackground=self.colors['toolbar_bg'])
        new_btn.pack(side=tk.LEFT, padx=2)
        
        # Save button - with dark text on light background
        save_btn = tk.Button(file_frame, text="Save", command=self.save_card,
                           bg=self.colors['button_bg'], 
                           fg=self.colors['button_fg'],
                           activebackground=self.colors['button_active_bg'],
                           activeforeground=self.colors['button_fg'],
                           highlightbackground=self.colors['toolbar_bg'])
        save_btn.pack(side=tk.LEFT, padx=2)
        
        # Export options
        export_frame = ttk.Frame(toolbar, style='Toolbar.TFrame')
        export_frame.pack(side=tk.LEFT, padx=20)
        
        # Export to PDF button - with dark background and VERY CLEARLY WHITE text
        pdf_btn = tk.Button(export_frame, text="Export PDF", 
                          command=self.generate_pdf,
                          bg="#0033cc", 
                          fg="#FFFFFF",
                          activebackground="#002280",
                          activeforeground="#FFFFFF",
                          highlightbackground=self.colors['toolbar_bg'],
                          font=('Helvetica', 11, 'bold'))
        pdf_btn.pack(side=tk.LEFT, padx=2)
        
        # Export to Markdown button - also with clear white text
        md_btn = tk.Button(export_frame, text="Export Markdown", 
                         command=self.export_markdown,
                         bg="#0033cc", 
                         fg="#FFFFFF",
                         activebackground="#002280",
                         activeforeground="#FFFFFF",
                         highlightbackground=self.colors['toolbar_bg'],
                         font=('Helvetica', 11, 'bold'))
        md_btn.pack(side=tk.LEFT, padx=2)
        
        # Front/Back toggle frame
        side_frame = ttk.Frame(toolbar, style='Toolbar.TFrame')
        side_frame.pack(side=tk.LEFT, padx=15)
        
        ttk.Label(side_frame, text="Card Side:").pack(side=tk.LEFT, padx=(0, 5))
        
        # Front button
        self.front_btn = tk.Button(side_frame, text="Front", width=6,
                                 command=lambda: self.switch_card_side("front"),
                                 bg=self.colors['button_active_bg'], 
                                 fg=self.colors['button_fg'],
                                 activebackground=self.colors['button_active_bg'],
                                 activeforeground=self.colors['button_fg'],
                                 highlightbackground=self.colors['toolbar_bg'],
                                 relief=tk.SUNKEN)
        self.front_btn.pack(side=tk.LEFT, padx=1)
        
        # Back button
        self.back_btn = tk.Button(side_frame, text="Back", width=6,
                                command=lambda: self.switch_card_side("back"),
                                bg=self.colors['button_bg'], 
                                fg=self.colors['button_fg'],
                                activebackground=self.colors['button_active_bg'],
                                activeforeground=self.colors['button_fg'],
                                highlightbackground=self.colors['toolbar_bg'],
                                relief=tk.RAISED)
        self.back_btn.pack(side=tk.LEFT, padx=1)
        
        # Orientation toggle frame
        orientation_frame = ttk.Frame(toolbar, style='Toolbar.TFrame')
        orientation_frame.pack(side=tk.LEFT, padx=15)
        
        ttk.Label(orientation_frame, text="Orientation:").pack(side=tk.LEFT, padx=(0, 5))
        
        # Portrait button
        self.portrait_btn = tk.Button(orientation_frame, text="Portrait", width=8,
                                    command=lambda: self.switch_orientation("portrait"),
                                    bg=self.colors['button_active_bg'], 
                                    fg=self.colors['button_fg'],
                                    activebackground=self.colors['button_active_bg'],
                                    activeforeground=self.colors['button_fg'],
                                    highlightbackground=self.colors['toolbar_bg'],
                                    relief=tk.SUNKEN)
        self.portrait_btn.pack(side=tk.LEFT, padx=1)
        
        # Landscape button
        self.landscape_btn = tk.Button(orientation_frame, text="Landscape", width=8,
                                     command=lambda: self.switch_orientation("landscape"),
                                     bg=self.colors['button_bg'], 
                                     fg=self.colors['button_fg'],
                                     activebackground=self.colors['button_active_bg'],
                                     activeforeground=self.colors['button_fg'],
                                     highlightbackground=self.colors['toolbar_bg'],
                                     relief=tk.RAISED)
        self.landscape_btn.pack(side=tk.LEFT, padx=1)
        
        # Card navigation section on the right
        nav_frame = ttk.Frame(toolbar, style='Toolbar.TFrame')
        nav_frame.pack(side=tk.RIGHT, padx=5)
        
        self.prev_btn = tk.Button(nav_frame, text="◀", command=self.prev_card, width=3,
                                bg=self.colors['button_bg'], 
                                fg=self.colors['button_fg'],
                                activebackground=self.colors['button_active_bg'],
                                activeforeground=self.colors['button_fg'],
                                highlightbackground=self.colors['toolbar_bg'])
        self.prev_btn.pack(side=tk.LEFT, padx=2)
        
        self.card_counter_var = tk.StringVar(value="Card 1 of 1")
        card_counter = ttk.Label(nav_frame, textvariable=self.card_counter_var)
        card_counter.pack(side=tk.LEFT, padx=5)
        
        self.next_btn = tk.Button(nav_frame, text="▶", command=self.next_card, width=3,
                                bg=self.colors['button_bg'], 
                                fg=self.colors['button_fg'],
                                activebackground=self.colors['button_active_bg'],
                                activeforeground=self.colors['button_fg'],
                                highlightbackground=self.colors['toolbar_bg'])
        self.next_btn.pack(side=tk.LEFT, padx=2)
        
        # Settings button
        settings_btn = tk.Button(toolbar, text="⚙", command=self.open_settings, width=3,
                               bg=self.colors['button_bg'], 
                               fg=self.colors['button_fg'],
                               activebackground=self.colors['button_active_bg'],
                               activeforeground=self.colors['button_fg'],
                               highlightbackground=self.colors['toolbar_bg'])
        settings_btn.pack(side=tk.RIGHT, padx=5)
    
    def setup_editor(self):
        """Set up the markdown editor pane"""
        editor_frame = ttk.Frame(self.editor_preview_frame)
        self.editor_preview_frame.add(editor_frame, weight=1)
        
        # Editor label showing which side is being edited
        self.editor_label_var = tk.StringVar(value="Editing Front Side")
        editor_label = ttk.Label(editor_frame, textvariable=self.editor_label_var)
        editor_label.pack(anchor="w", pady=(0, 5))
        
        # Editor with line numbers and syntax features
        editor_container = ttk.Frame(editor_frame)
        editor_container.pack(fill=tk.BOTH, expand=True)
        
        # Text widget for editing
        self.markdown_text = tk.Text(
            editor_container, 
            wrap=tk.WORD, 
            font=("Menlo", 13),
            background=self.colors['editor_bg'],
            foreground=self.colors['fg'],
            insertbackground=self.colors['fg'],
            padx=10,
            pady=10,
            undo=True,  # Enable undo/redo
            maxundo=50   # Number of undo levels
        )
        self.markdown_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.markdown_text.bind("<KeyRelease>", self.on_text_change)
        
        # Scrollbar for the editor
        editor_scrollbar = ttk.Scrollbar(editor_container, command=self.markdown_text.yview)
        editor_scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.markdown_text.config(yscrollcommand=editor_scrollbar.set)
        
        # Simple formatting toolbar for markdown
        format_toolbar = ttk.Frame(editor_frame)
        format_toolbar.pack(fill=tk.X, pady=(5, 0))
        
        # Formatting buttons - Using standard tk Buttons with correct styling
        bold_btn = tk.Button(format_toolbar, text="Bold", width=8,
                           command=lambda: self.insert_markdown_format("**", "**"),
                           bg=self.colors['button_bg'], 
                           fg=self.colors['button_fg'],
                           activebackground=self.colors['button_active_bg'],
                           activeforeground=self.colors['button_fg'],
                           highlightbackground=self.colors['bg'])
        bold_btn.pack(side=tk.LEFT, padx=2)
        
        italic_btn = tk.Button(format_toolbar, text="Italic", width=8,
                             command=lambda: self.insert_markdown_format("*", "*"),
                             bg=self.colors['button_bg'], 
                             fg=self.colors['button_fg'],
                             activebackground=self.colors['button_active_bg'],
                             activeforeground=self.colors['button_fg'],
                             highlightbackground=self.colors['bg'])
        italic_btn.pack(side=tk.LEFT, padx=2)
        
        code_btn = tk.Button(format_toolbar, text="Code", width=8,
                           command=lambda: self.insert_markdown_format("`", "`"),
                           bg=self.colors['button_bg'], 
                           fg=self.colors['button_fg'],
                           activebackground=self.colors['button_active_bg'],
                           activeforeground=self.colors['button_fg'],
                           highlightbackground=self.colors['bg'])
        code_btn.pack(side=tk.LEFT, padx=2)
        
        list_btn = tk.Button(format_toolbar, text="List Item", width=8,
                           command=lambda: self.insert_markdown_line("- "),
                           bg=self.colors['button_bg'], 
                           fg=self.colors['button_fg'],
                           activebackground=self.colors['button_active_bg'],
                           activeforeground=self.colors['button_fg'],
                           highlightbackground=self.colors['bg'])
        list_btn.pack(side=tk.LEFT, padx=2)
    
    def setup_preview(self):
        """Set up the preview pane"""
        preview_frame = ttk.Frame(self.editor_preview_frame)
        self.editor_preview_frame.add(preview_frame, weight=1)
        
        # Preview label showing which side is being previewed
        self.preview_label_var = tk.StringVar(value="Front Side Preview")
        preview_label = ttk.Label(preview_frame, textvariable=self.preview_label_var)
        preview_label.pack(anchor="w", pady=(0, 5))
        
        # Preview container with card aspect ratio
        self.preview_container = ttk.Frame(preview_frame, style='Card.TFrame')
        self.preview_container.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)
        
        # Canvas for rendering the card preview
        self.preview_canvas = tk.Canvas(
            self.preview_container,
            bg=self.colors['preview_bg'],
            highlightthickness=0
        )
        self.preview_canvas.pack(fill=tk.BOTH, expand=True)
    
    def setup_status_bar(self, parent):
        """Set up the status bar"""
        status_bar = ttk.Frame(parent)
        status_bar.pack(fill=tk.X, pady=(5, 0))
        
        # Status message on the left
        self.status_message = tk.StringVar(value="Ready")
        status_label = ttk.Label(status_bar, textvariable=self.status_message)
        status_label.pack(side=tk.LEFT)
        
        # Character count on the right
        self.char_count = tk.StringVar(value="0 characters")
        char_count_label = ttk.Label(status_bar, textvariable=self.char_count)
        char_count_label.pack(side=tk.RIGHT)
    
    def setup_shortcuts(self):
        """Set up keyboard shortcuts"""
        self.root.bind("<Command-s>", lambda e: self.save_card())
        self.root.bind("<Control-s>", lambda e: self.save_card())
        self.root.bind("<Command-n>", lambda e: self.new_card())
        self.root.bind("<Control-n>", lambda e: self.new_card())
        self.root.bind("<Command-p>", lambda e: self.generate_pdf())
        self.root.bind("<Control-p>", lambda e: self.generate_pdf())
        self.root.bind("<Command-e>", lambda e: self.export_markdown())
        self.root.bind("<Control-e>", lambda e: self.export_markdown())
        self.root.bind("<Command-z>", lambda e: self.markdown_text.edit_undo())
        self.root.bind("<Control-z>", lambda e: self.markdown_text.edit_undo())
        self.root.bind("<Command-Shift-z>", lambda e: self.markdown_text.edit_redo())
        self.root.bind("<Control-Shift-z>", lambda e: self.markdown_text.edit_redo())
        self.root.bind("<Control-y>", lambda e: self.markdown_text.edit_redo())
        
        # Add shortcuts for front/back switching
        self.root.bind("<Command-1>", lambda e: self.switch_card_side("front"))
        self.root.bind("<Control-1>", lambda e: self.switch_card_side("front"))
        self.root.bind("<Command-2>", lambda e: self.switch_card_side("back"))
        self.root.bind("<Control-2>", lambda e: self.switch_card_side("back"))
    
    def setup_autosave(self):
        """Set up autosave functionality"""
        def autosave():
            if self.cards:
                # Save current card content
                self.save_current_side_content()
                
                # Update status
                self.status_message.set("Autosaved")
                # Clear status after 2 seconds
                self.root.after(2000, lambda: self.status_message.set("Ready"))
            
            # Schedule next autosave
            self.autosave_timer = self.root.after(30000, autosave)  # 30 seconds
        
        # Start autosave timer
        self.autosave_timer = self.root.after(30000, autosave)
    
    def save_current_side_content(self):
        """Save the current side's content to the card data structure"""
        if self.cards:
            content = self.markdown_text.get("1.0", tk.END).strip()
            
            # Update card content for current side
            if self.current_side == "front":
                self.cards[self.current_card_index]["front"] = content
            else:
                self.cards[self.current_card_index]["back"] = content
                
            # Update card title (always from front)
            if self.current_side == "front":
                title = self.extract_title(content)
                self.cards[self.current_card_index]["title"] = title
            
            return content
    
    def insert_markdown_format(self, prefix, suffix):
        """Insert markdown formatting around selected text"""
        try:
            # Get selection or insert position
            if self.markdown_text.tag_ranges("sel"):
                selection = self.markdown_text.get(tk.SEL_FIRST, tk.SEL_LAST)
                self.markdown_text.delete(tk.SEL_FIRST, tk.SEL_LAST)
                self.markdown_text.insert(tk.INSERT, f"{prefix}{selection}{suffix}")
            else:
                self.markdown_text.insert(tk.INSERT, f"{prefix}{suffix}")
                # Move cursor between tags
                current_pos = self.markdown_text.index(tk.INSERT)
                self.markdown_text.mark_set(tk.INSERT, f"{current_pos}-{len(suffix)}c")
        except:
            pass
    
    def insert_markdown_line(self, prefix):
        """Insert a new line with prefix at the beginning"""
        try:
            # Get current line
            linestart = self.markdown_text.index(tk.INSERT + " linestart")
            lineend = self.markdown_text.index(tk.INSERT + " lineend")
            
            # If not at beginning of a line, insert newline first
            if self.markdown_text.index(tk.INSERT) != linestart:
                self.markdown_text.insert(tk.INSERT, f"\n{prefix}")
            else:
                self.markdown_text.insert(tk.INSERT, prefix)
        except:
            pass
    
    def on_text_change(self, event):
        """Handle text changes in the editor"""
        # Check if text ends with "print"
        content = self.markdown_text.get("1.0", tk.END)
        if content.strip().endswith("print"):
            # Remove "print" from the text
            self.markdown_text.delete("end-6c", "end")
            # Generate PDF
            self.generate_pdf()
        else:
            # Update preview
            self.update_preview()
            
            # Update character count
            char_count = len(content.strip())
            self.char_count.set(f"{char_count} characters")
            
            # Save current card content
            if self.cards:
                self.save_current_side_content()
    
    def extract_title(self, markdown_content):
        """Extract title from markdown content"""
        title = "Untitled Card"
        title_match = re.search(r'^# (.+)$', markdown_content, re.MULTILINE)
        if title_match:
            title = title_match.group(1).strip()
        return title
    
    def extract_tags(self, markdown_content):
        """Extract tags from markdown content"""
        tags = ""
        tags_match = re.search(r'^Tags: (.+)$', markdown_content, re.MULTILINE)
        if tags_match:
            tags = tags_match.group(1).strip()
        return tags
    
    def update_preview(self):
        """Update the card preview"""
        # Get markdown content for current side
        if self.current_side == "front":
            markdown_content = self.markdown_text.get("1.0", tk.END)
        else:
            markdown_content = self.markdown_text.get("1.0", tk.END)
        
        # Extract title and tags
        title = self.extract_title(markdown_content)
        tags = self.extract_tags(markdown_content)
        
        # Create a simplified content for preview (remove title and tags)
        content = markdown_content
        if title != "Untitled Card":
            content = content.replace(f"# {title}", "", 1)
        if tags:
            content = content.replace(f"Tags: {tags}", "", 1)
        
        # Clear canvas
        self.preview_canvas.delete("all")
        
        # Get canvas size
        canvas_width = self.preview_canvas.winfo_width()
        canvas_height = self.preview_canvas.winfo_height()
        
        # Skip redraw if canvas is not yet sized
        if canvas_width <= 1 or canvas_height <= 1:
            self.preview_canvas.after(100, self.update_preview)
            return
        
        # Determine card dimensions based on orientation and size
        if self.card_size == "3x5":
            card_ratio = 5/3 if self.card_orientation == "portrait" else 3/5
        elif self.card_size == "4x6":
            card_ratio = 6/4 if self.card_orientation == "portrait" else 4/6
        else:  # Default to 3x5
            card_ratio = 5/3 if self.card_orientation == "portrait" else 3/5
        
        # Calculate card size to fit in canvas while maintaining aspect ratio
        if canvas_width / canvas_height > card_ratio:
            # Canvas is wider than card ratio, height is limiting factor
            card_height = int(canvas_height * 0.9)
            card_width = int(card_height * card_ratio)
        else:
            # Canvas is taller than card ratio, width is limiting factor
            card_width = int(canvas_width * 0.9)
            card_height = int(card_width / card_ratio)
        
        # Calculate position to center the card
        x_offset = (canvas_width - card_width) // 2
        y_offset = (canvas_height - card_height) // 2
        
        # Draw card background
        card_bg_color = "#FFFFFF" if self.card_theme == "light" else "#2D2D30"
        card_border_color = "#CCCCCC" if self.card_theme == "light" else "#555555"
        card_text_color = "#000000" if self.card_theme == "light" else "#FFFFFF"
        
        # Draw card with shadow effect
        shadow_offset = 5
        self.preview_canvas.create_rectangle(
            x_offset + shadow_offset, y_offset + shadow_offset, 
            x_offset + card_width + shadow_offset, y_offset + card_height + shadow_offset,
            fill="#AAAAAA", outline="#AAAAAA", width=0)
        
        self.preview_canvas.create_rectangle(
            x_offset, y_offset, x_offset + card_width, y_offset + card_height,
            fill=card_bg_color, outline=card_border_color, width=2)
        
        # Add discrete side indicator in the corner (only if enabled)
        if self.show_side_indicator:
            indicator_text = "F" if self.current_side == "front" else "B"
            
            self.preview_canvas.create_text(
                x_offset + card_width - 10, y_offset + 10,
                text=indicator_text,
                font=("Helvetica", 8),
                fill="#999999",
                anchor="ne"
            )
        
        # Calculate margins and content areas
        margin = int(card_width * 0.06)  # 6% of width as margin
        title_height = int(card_height * 0.15)  # 15% of height for title
        tags_height = int(card_height * 0.1)  # 10% of height for tags
        content_height = card_height - title_height - tags_height - (margin * 2)
        
        # Draw title area
        if title != "Untitled Card":
            title_bg = "#F0F0F0" if self.card_theme == "light" else "#3D3D40"
            self.preview_canvas.create_rectangle(
                x_offset, y_offset, 
                x_offset + card_width, y_offset + title_height,
                fill=title_bg, outline=card_border_color, width=1)
            
            self.preview_canvas.create_text(
                x_offset + (card_width // 2), y_offset + (title_height // 2),
                text=title, 
                font=("Helvetica", self.title_font_size, "bold"),
                fill=card_text_color,
                width=card_width - (margin * 2)
            )
        
        # Draw tags area
        if tags:
            tags_y = y_offset + card_height - tags_height
            tags_bg = "#F0F0F0" if self.card_theme == "light" else "#3D3D40"
            
            self.preview_canvas.create_rectangle(
                x_offset, tags_y, 
                x_offset + card_width, y_offset + card_height,
                fill=tags_bg, outline=card_border_color, width=1)
            
            self.preview_canvas.create_text(
                x_offset + (card_width // 2), tags_y + (tags_height // 2),
                text=tags, 
                font=("Helvetica", self.tags_font_size),
                fill="#666666" if self.card_theme == "light" else "#AAAAAA",
                width=card_width - (margin * 2)
            )
        
        # Draw content area
        content_y = y_offset + title_height + margin
        
        # Process content - convert simple markdown
        display_content = content.strip()
        
        # Replace bold
        display_content = re.sub(r'\*\*(.*?)\*\*', r'\1', display_content)
        
        # Replace italic
        display_content = re.sub(r'\*(.*?)\*', r'\1', display_content)
        
        # Replace inline code
        display_content = re.sub(r'`(.*?)`', r'\1', display_content)
        
        # Convert bullet lists
        lines = display_content.split('\n')
        for i, line in enumerate(lines):
            if line.startswith('- '):
                lines[i] = '• ' + line[2:]
                
        display_content = '\n'.join(lines)
        
        # Draw content text
        self.preview_canvas.create_text(
            x_offset + margin, content_y,
            anchor="nw",
            text=display_content, 
            font=("Helvetica", self.content_font_size),
            fill=card_text_color,
            width=card_width - (margin * 2)
        )
    
    def update_card_counter(self):
        """Update the card counter display"""
        self.card_counter_var.set(f"Card {self.current_card_index + 1} of {len(self.cards)}")
        
        # Enable/disable navigation buttons based on position
        if self.current_card_index <= 0:
            self.prev_btn.config(state=tk.DISABLED)
        else:
            self.prev_btn.config(state=tk.NORMAL)
            
        if self.current_card_index >= len(self.cards) - 1:
            self.next_btn.config(state=tk.DISABLED)
        else:
            self.next_btn.config(state=tk.NORMAL)
    
    def new_card(self):
        """Create a new card"""
        # Save current card
        if self.cards:
            self.save_current_side_content()
        
        # Create new card with front and empty back
        self.cards.append({
            "front": "# New Card\n\nContent goes here...\n\nTags: #new", 
            "back": "",  # Empty back by default
            "title": "New Card"
        })
        
        # Switch to the new card
        self.current_card_index = len(self.cards) - 1
        
        # Update UI to show the front side by default
        self.switch_card_side("front")
        
        # Update card counter
        self.update_card_counter()
        
        # Focus editor
        self.markdown_text.focus_set()
    
    def save_card(self):
        """Save the current card (primarily used for explicit save button)"""
        if self.cards:
            # Update card content
            self.save_current_side_content()
            
            # Update status
            self.status_message.set("Card saved")
            # Clear status after 2 seconds
            self.root.after(2000, lambda: self.status_message.set("Ready"))
    
    def prev_card(self):
        """Navigate to the previous card"""
        if self.current_card_index > 0:
            # Save current card
            self.save_current_side_content()
            
            # Move to previous card
            self.current_card_index -= 1
            
            # Update UI to show the current side of the new card
            if self.current_side == "front":
                content = self.cards[self.current_card_index]["front"]
            else:
                content = self.cards[self.current_card_index]["back"]
                
            self.markdown_text.delete("1.0", tk.END)
            self.markdown_text.insert("1.0", content)
            self.update_preview()
            self.update_card_counter()
    
    def next_card(self):
        """Navigate to the next card"""
        if self.current_card_index < len(self.cards) - 1:
            # Save current card
            self.save_current_side_content()
            
            # Move to next card
            self.current_card_index += 1
            
            # Update UI to show the current side of the new card
            if self.current_side == "front":
                content = self.cards[self.current_card_index]["front"]
            else:
                content = self.cards[self.current_card_index]["back"]
                
            self.markdown_text.delete("1.0", tk.END)
            self.markdown_text.insert("1.0", content)
            self.update_preview()
            self.update_card_counter()
    
    def switch_card_side(self, side):
        """Switch between front and back sides of the card"""
        if side == self.current_side:
            return  # Already on this side
            
        # Save current content
        if self.cards:
            self.save_current_side_content()
        
        # Update current side
        self.current_side = side
        
        # Update buttons
        if side == "front":
            self.front_btn.config(relief=tk.SUNKEN, bg=self.colors['button_active_bg'])
            self.back_btn.config(relief=tk.RAISED, bg=self.colors['button_bg'])
            self.editor_label_var.set("Editing Front Side")
            self.preview_label_var.set("Front Side Preview")
        else:
            self.front_btn.config(relief=tk.RAISED, bg=self.colors['button_bg'])
            self.back_btn.config(relief=tk.SUNKEN, bg=self.colors['button_active_bg'])
            self.editor_label_var.set("Editing Back Side")
            self.preview_label_var.set("Back Side Preview")
        
        # Load content for the selected side
        if self.cards:
            if side == "front":
                content = self.cards[self.current_card_index]["front"]
            else:
                content = self.cards[self.current_card_index]["back"]
                
            self.markdown_text.delete("1.0", tk.END)
            self.markdown_text.insert("1.0", content)
            
        # Update preview
        self.update_preview()
    
    def switch_orientation(self, orientation):
        """Switch between portrait and landscape orientation"""
        if orientation == self.card_orientation:
            return  # Already in this orientation
            
        # Update orientation
        self.card_orientation = orientation
        
        # Update buttons
        if orientation == "portrait":
            self.portrait_btn.config(relief=tk.SUNKEN, bg=self.colors['button_active_bg'])
            self.landscape_btn.config(relief=tk.RAISED, bg=self.colors['button_bg'])
        else:
            self.portrait_btn.config(relief=tk.RAISED, bg=self.colors['button_bg'])
            self.landscape_btn.config(relief=tk.SUNKEN, bg=self.colors['button_active_bg'])
        
        # Save settings
        self.save_settings()
        
        # Update preview
        self.update_preview()
    
    def open_settings(self):
        """Open the settings dialog"""
        settings_window = tk.Toplevel(self.root)
        settings_window.title("Cardify Settings")
        settings_window.geometry("500x450")
        settings_window.resizable(False, False)
        settings_window.transient(self.root)
        settings_window.grab_set()  # Make window modal
        
        # Configure with the same style
        settings_window.configure(bg=self.colors['bg'])
        
        # Create frame for card settings
        card_settings_frame = ttk.Frame(settings_window)
        card_settings_frame.pack(fill=tk.BOTH, expand=True, padx=20, pady=20)
        
        # Card size options
        ttk.Label(card_settings_frame, text="Card Size:").grid(row=0, column=0, sticky="w", padx=10, pady=10)
        card_size_var = tk.StringVar(value=self.card_size)
        card_size_combo = ttk.Combobox(card_settings_frame, textvariable=card_size_var, 
                                     values=["3x5", "4x6", "5x7"], width=10)
        card_size_combo.grid(row=0, column=1, sticky="w", padx=10, pady=10)
        
        # Card orientation
        ttk.Label(card_settings_frame, text="Orientation:").grid(row=1, column=0, sticky="w", padx=10, pady=10)
        orientation_var = tk.StringVar(value=self.card_orientation)
        orientation_frame = ttk.Frame(card_settings_frame)
        orientation_frame.grid(row=1, column=1, sticky="w", padx=10, pady=10)
        
        # Use tk.Radiobutton instead of ttk for better visibility
        tk.Radiobutton(orientation_frame, text="Portrait", variable=orientation_var, 
                     value="portrait", bg=self.colors['bg'], 
                     fg=self.colors['fg'],
                     selectcolor=self.colors['bg']).pack(side=tk.LEFT, padx=(0, 10))
        tk.Radiobutton(orientation_frame, text="Landscape", variable=orientation_var, 
                     value="landscape", bg=self.colors['bg'], 
                     fg=self.colors['fg'],
                     selectcolor=self.colors['bg']).pack(side=tk.LEFT)
        
        # Card theme
        ttk.Label(card_settings_frame, text="Theme:").grid(row=2, column=0, sticky="w", padx=10, pady=10)
        theme_var = tk.StringVar(value=self.card_theme)
        theme_frame = ttk.Frame(card_settings_frame)
        theme_frame.grid(row=2, column=1, sticky="w", padx=10, pady=10)
        
        # Use tk.Radiobutton for theme selection with correct colors
        tk.Radiobutton(theme_frame, text="Light", variable=theme_var, 
                     value="light", bg=self.colors['bg'], 
                     fg=self.colors['fg'],
                     selectcolor=self.colors['bg']).pack(side=tk.LEFT, padx=(0, 10))
        tk.Radiobutton(theme_frame, text="Dark", variable=theme_var, 
                     value="dark", bg=self.colors['bg'], 
                     fg=self.colors['fg'],
                     selectcolor=self.colors['bg']).pack(side=tk.LEFT)
        
        # Font sizes
        ttk.Label(card_settings_frame, text="Content Font Size:").grid(row=3, column=0, sticky="w", padx=10, pady=10)
        content_size_var = tk.IntVar(value=self.content_font_size)
        content_size_spinner = ttk.Spinbox(card_settings_frame, from_=8, to=20, 
                                         textvariable=content_size_var, width=5)
        content_size_spinner.grid(row=3, column=1, sticky="w", padx=10, pady=10)
        
        ttk.Label(card_settings_frame, text="Title Font Size:").grid(row=4, column=0, sticky="w", padx=10, pady=10)
        title_size_var = tk.IntVar(value=self.title_font_size)
        title_size_spinner = ttk.Spinbox(card_settings_frame, from_=12, to=28, 
                                         textvariable=title_size_var, width=5)
        title_size_spinner.grid(row=4, column=1, sticky="w", padx=10, pady=10)
        
        ttk.Label(card_settings_frame, text="Tags Font Size:").grid(row=5, column=0, sticky="w", padx=10, pady=10)
        tags_size_var = tk.IntVar(value=self.tags_font_size)
        tags_size_spinner = ttk.Spinbox(card_settings_frame, from_=8, to=16, 
                                         textvariable=tags_size_var, width=5)
        tags_size_spinner.grid(row=5, column=1, sticky="w", padx=10, pady=10)
        
        # Side indicator option
        ttk.Label(card_settings_frame, text="Side Indicator:").grid(row=6, column=0, sticky="w", padx=10, pady=10)
        indicator_var = tk.BooleanVar(value=self.show_side_indicator)
        indicator_check = tk.Checkbutton(card_settings_frame, text="Show side indicator (F/B)",
                                      variable=indicator_var,
                                      bg=self.colors['bg'],
                                      highlightbackground=self.colors['bg'])
        indicator_check.grid(row=6, column=1, sticky="w", padx=10, pady=10)
        
        # Buttons at the bottom
        button_frame = ttk.Frame(settings_window)
        button_frame.pack(fill=tk.X, padx=20, pady=20)
        
        cancel_btn = tk.Button(button_frame, text="Cancel", 
                             command=settings_window.destroy,
                             bg=self.colors['button_bg'], 
                             fg=self.colors['button_fg'],
                             activebackground=self.colors['button_active_bg'],
                             activeforeground=self.colors['button_fg'],
                             highlightbackground=self.colors['bg'])
        cancel_btn.pack(side=tk.RIGHT, padx=5)
        
        save_btn = tk.Button(button_frame, text="Save Settings", 
                           command=lambda: self.save_settings_dialog(
                                settings_window,
                                card_size_var.get(),
                                orientation_var.get(),
                                theme_var.get(),
                                content_size_var.get(),
                                title_size_var.get(),
                                tags_size_var.get(),
                                indicator_var.get()
                            ),
                           bg="#0033cc", 
                           fg="#FFFFFF",
                           activebackground="#002280",
                           activeforeground="#FFFFFF",
                           highlightbackground=self.colors['bg'])
        save_btn.pack(side=tk.RIGHT, padx=5)
    
    def save_settings_dialog(self, window, card_size, orientation, theme, 
                            content_size, title_size, tags_size, show_indicator):
        """Save settings from the dialog"""
        # Update settings
        self.card_size = card_size
        self.card_orientation = orientation
        self.card_theme = theme
        self.content_font_size = content_size
        self.title_font_size = title_size
        self.tags_font_size = tags_size
        self.show_side_indicator = show_indicator
        
        # Update orientation buttons
        if orientation == "portrait":
            self.portrait_btn.config(relief=tk.SUNKEN, bg=self.colors['button_active_bg'])
            self.landscape_btn.config(relief=tk.RAISED, bg=self.colors['button_bg'])
        else:
            self.portrait_btn.config(relief=tk.RAISED, bg=self.colors['button_bg'])
            self.landscape_btn.config(relief=tk.SUNKEN, bg=self.colors['button_active_bg'])
        
        # Save to config file
        self.save_settings()
        
        # Update UI
        self.update_preview()
        
        # Close dialog
        window.destroy()
        
        # Show confirmation
        self.status_message.set("Settings saved")
        self.root.after(2000, lambda: self.status_message.set("Ready"))
    
    def export_markdown(self):
        """Export the card to a markdown file without duplicating titles"""
        # Save current content
        self.save_current_side_content()
        
        # Get card title for filename
        title = self.cards[self.current_card_index]["title"]
        
        # Get the front and back content
        front_content = self.cards[self.current_card_index]["front"]
        back_content = self.cards[self.current_card_index]["back"].strip()
        
        # Extract titles and tags
        front_title = self.extract_title(front_content)
        front_tags = self.extract_tags(front_content)
        
        # Only include back content if it's not empty
        include_back = len(back_content) > 0
        
        if include_back:
            back_title = self.extract_title(back_content)
            back_tags = self.extract_tags(back_content)
        
        # Process the front content - remove the title
        if front_title != "Untitled Card":
            front_content_clean = re.sub(r'^# ' + re.escape(front_title) + r'$', '', front_content, flags=re.MULTILINE)
        else:
            front_content_clean = front_content
            
        # Remove tags from content for better formatting
        if front_tags:
            front_content_clean = re.sub(r'^Tags: ' + re.escape(front_tags) + r'$', '', front_content_clean, flags=re.MULTILINE)
        
        # Clean up any redundant newlines
        front_content_clean = re.sub(r'\n{3,}', '\n\n', front_content_clean)
        
        # Format the combined markdown
        if include_back:
            # Process back content
            if back_title == front_title:
                back_content_clean = re.sub(r'^# ' + re.escape(back_title) + r'$', '', back_content, flags=re.MULTILINE)
            else:
                back_content_clean = back_content
                
            if back_tags:
                back_content_clean = re.sub(r'^Tags: ' + re.escape(back_tags) + r'$', '', back_content_clean, flags=re.MULTILINE)
                
            back_content_clean = re.sub(r'\n{3,}', '\n\n', back_content_clean)
            
            # Create content with front and back
            content = f"""# {front_title}

{front_content_clean.strip()}

Tags: {front_tags}

## Back Side

{back_content_clean.strip()}
"""
            # Add back tags if they exist
            if back_tags:
                content += f"\nTags: {back_tags}"
        else:
            # Only include front content
            content = f"""# {front_title}

{front_content_clean.strip()}

Tags: {front_tags}
"""
        
        # Ask user where to save the file
        file_path = filedialog.asksaveasfilename(
            defaultextension=".md",
            filetypes=[("Markdown files", "*.md")],
            title="Save Markdown As",
            initialfile=f"{title}.md" if title != "Untitled Card" else "card.md"
        )
        
        if file_path:
            try:
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write(content)
                
                # Show success message
                self.status_message.set(f"Markdown saved to {os.path.basename(file_path)}")
                
                # Clear status after 3 seconds
                self.root.after(3000, lambda: self.status_message.set("Ready"))
                
            except Exception as e:
                messagebox.showerror("Error", f"Failed to save file: {e}")
    
    def generate_pdf(self):
        """Generate PDF from the current card (including both front and back)"""
        # Save current content
        self.save_current_side_content()
        
        # Get front content
        front_content = self.cards[self.current_card_index]["front"]
        
        # Check if there's any actual back content
        back_content = self.cards[self.current_card_index]["back"].strip()
        has_back_content = len(back_content) > 0
        
        # Extract title and tags from front
        title = self.extract_title(front_content)
        front_tags = self.extract_tags(front_content)
        
        # Remove title and tags from content for processing
        front_content_clean = front_content
        
        if title != "Untitled Card":
            title_pattern = re.compile(r'^# ' + re.escape(title) + r'$', re.MULTILINE)
            front_content_clean = title_pattern.sub('', front_content_clean)
        
        if front_tags:
            front_tags_pattern = re.compile(r'^Tags: ' + re.escape(front_tags) + r'$', re.MULTILINE)
            front_content_clean = front_tags_pattern.sub('', front_content_clean)
        
        # Ask user where to save the PDF
        file_path = filedialog.asksaveasfilename(
            defaultextension=".pdf",
            filetypes=[("PDF files", "*.pdf")],
            title="Save PDF as",
            initialfile=f"{title}.pdf" if title != "Untitled Card" else "card.pdf"
        )
        
        if file_path:
            try:
                # Set PDF dimensions based on card size and orientation
                if self.card_size == "3x5":
                    width, height = 5*inch, 3*inch
                elif self.card_size == "4x6":
                    width, height = 6*inch, 4*inch
                elif self.card_size == "5x7":
                    width, height = 7*inch, 5*inch
                else:
                    width, height = 5*inch, 3*inch
                
                if self.card_orientation == "landscape":
                    width, height = height, width
                
                # Create the PDF document
                pdf = SimpleDocTemplate(
                    file_path,
                    pagesize=(width, height),
                    leftMargin=0.2*inch,
                    rightMargin=0.2*inch,
                    topMargin=0.2*inch,
                    bottomMargin=0.2*inch
                )
                
                # Create styles
                styles = getSampleStyleSheet()
                
                title_style = ParagraphStyle(
                    'Title',
                    parent=styles['Title'],
                    fontSize=self.title_font_size,
                    alignment=TA_CENTER,
                    spaceAfter=0.1*inch,
                    textColor=colors.black if self.card_theme == "light" else colors.white
                )
                
                content_style = ParagraphStyle(
                    'Content',
                    parent=styles['Normal'],
                    fontSize=self.content_font_size,
                    spaceAfter=0.05*inch,
                    textColor=colors.black if self.card_theme == "light" else colors.white
                )
                
                tags_style = ParagraphStyle(
                    'Tags',
                    parent=styles['Normal'],
                    fontSize=self.tags_font_size,
                    alignment=TA_LEFT,
                    textColor=colors.gray
                )
                
                side_indicator_style = ParagraphStyle(
                    'SideIndicator',
                    parent=styles['Normal'],
                    fontSize=8,
                    alignment=TA_RIGHT,
                    textColor=colors.gray
                )
                
                # Create elements for front side
                front_elements = []
                
                # Add side indicator (small, discreet)
                if self.show_side_indicator:
                    front_elements.append(Paragraph("F", side_indicator_style))
                
                # Add title
                if title != "Untitled Card":
                    front_elements.append(Paragraph(html.escape(title), title_style))
                    front_elements.append(Spacer(1, 0.1*inch))
                
                # Process front content
                front_content_clean = front_content_clean.strip()
                front_paragraphs = front_content_clean.split('\n\n')
                for p in front_paragraphs:
                    if p.strip():
                        # Handle bullet lists
                        if p.startswith('- '):
                            lines = p.split('\n')
                            for line in lines:
                                if line.startswith('- '):
                                    bullet_text = f"• {line[2:].strip()}"
                                    front_elements.append(Paragraph(bullet_text, content_style))
                        else:
                            # Process other markdown elements
                            # Bold
                            p = re.sub(r'\*\*(.*?)\*\*', r'<b>\1</b>', p)
                            # Italic
                            p = re.sub(r'\*(.*?)\*', r'<i>\1</i>', p)
                            # Code
                            p = re.sub(r'`(.*?)`', r'<code>\1</code>', p)
                            
                            front_elements.append(Paragraph(p, content_style))
                
                # Add front tags
                if front_tags:
                    front_elements.append(Spacer(1, 0.1*inch))
                    front_elements.append(Paragraph(html.escape(front_tags), tags_style))
                
                # Only process back if it has content
                if has_back_content:
                    # Add page break after front side
                    front_elements.append(PageBreak())
                    
                    # Create elements for back side
                    back_elements = []
                    
                    # Extract back title and tags if they exist
                    back_title = self.extract_title(back_content)
                    back_tags = self.extract_tags(back_content)
                    
                    # Process back content - removing title and tags
                    back_content_clean = back_content
                    
                    if back_title != "Untitled Card":
                        back_title_pattern = re.compile(r'^# ' + re.escape(back_title) + r'$', re.MULTILINE)
                        back_content_clean = back_title_pattern.sub('', back_content_clean)
                    
                    if back_tags:
                        back_tags_pattern = re.compile(r'^Tags: ' + re.escape(back_tags) + r'$', re.MULTILINE)
                        back_content_clean = back_tags_pattern.sub('', back_content_clean)
                    
                    # Add side indicator
                    if self.show_side_indicator:
                        back_elements.append(Paragraph("B", side_indicator_style))
                    
                    # Add title to back
                    if back_title != "Untitled Card":
                        back_elements.append(Paragraph(html.escape(back_title), title_style))
                        back_elements.append(Spacer(1, 0.1*inch))
                    
                    # Process back content
                    back_content_clean = back_content_clean.strip()
                    back_paragraphs = back_content_clean.split('\n\n')
                    for p in back_paragraphs:
                        if p.strip():
                            # Handle bullet lists
                            if p.startswith('- '):
                                lines = p.split('\n')
                                for line in lines:
                                    if line.startswith('- '):
                                        bullet_text = f"• {line[2:].strip()}"
                                        back_elements.append(Paragraph(bullet_text, content_style))
                            else:
                                # Process other markdown elements
                                # Bold
                                p = re.sub(r'\*\*(.*?)\*\*', r'<b>\1</b>', p)
                                # Italic
                                p = re.sub(r'\*(.*?)\*', r'<i>\1</i>', p)
                                # Code
                                p = re.sub(r'`(.*?)`', r'<code>\1</code>', p)
                                
                                back_elements.append(Paragraph(p, content_style))
                    
                    # Add back tags
                    if back_tags:
                        back_elements.append(Spacer(1, 0.1*inch))
                        back_elements.append(Paragraph(html.escape(back_tags), tags_style))
                    
                    # Combine elements
                    all_elements = front_elements + back_elements
                else:
                    # Only include front elements
                    all_elements = front_elements
                
                # Build the PDF
                pdf.build(all_elements)
                
                # Show success message
                self.status_message.set(f"PDF saved to {os.path.basename(file_path)}")
                
                # Open the PDF
                if os.name == 'posix':  # macOS or Linux
                    os.system(f"open '{file_path}'")
                elif os.name == 'nt':  # Windows
                    os.system(f'start "" "{file_path}"')
                
                # Clear status after 3 seconds
                self.root.after(3000, lambda: self.status_message.set("Ready"))
                
            except Exception as e:
                messagebox.showerror("Error", f"Failed to generate PDF: {e}")
                print(f"PDF Generation Error Details: {e}")  # Print more details for debugging

def main():
    root = tk.Tk()
    app = CardifyApp(root)
    root.mainloop()

if __name__ == "__main__":
    main()
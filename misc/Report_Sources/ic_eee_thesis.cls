% Giordano Scarciotti
% https://www.imperial.ac.uk/people/g.scarciotti
% LaTeX class for the final report of the MEng/BEng/MSc degrees of the Electrical and Electronic Engineering Department at Imperial College London
% Version 1.2.1 - 13/02/2025
% Approved by the EEE Department

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%% DO NOT MODIFY THIS FILE %%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

\PassOptionsToPackage{dvipsnames}{xcolor}

\DeclareOption*{\PassOptionsToClass{\CurrentOption}{book}}
\ProcessOptions\relax

\NeedsTeXFormat{LaTeX2e}
\ProvidesClass{ic_eee_thesis}[2023/06/09 - Giordano Scarciotti - Imperial College London Thesis Format]
\LoadClass[a4paper]{book}

\RequirePackage{pgfcore}
\RequirePackage{geometry} 
\RequirePackage{bookmark}
\RequirePackage{graphicx}
\RequirePackage{setspace}
\RequirePackage{kantlipsum}
\RequirePackage{tabularx}
\RequirePackage{array} 

% --- REMOVE RED HIGHLIGHT BOXES FROM HYPERLINKS ---
\hypersetup{
    pdfborder={0 0 0}
}

\RequirePackage{fontspec}

\RequirePackage{polyglossia}
\setdefaultlanguage{english}

\RequirePackage{minitoc}

\makeatletter
\def\input@path{{chapters/}}
\makeatother

\RequirePackage[printonlyused]{acronym}

\RequirePackage{ifthen}
\newboolean{list_of_tables}
\newboolean{list_of_figures}
\newboolean{acknowledgement}
\newboolean{MEngBEng}
\newboolean{acronyms}
\newboolean{edge_labels}
\newboolean{final_thesis}
\newboolean{double_spacing}

\newlength{\logowidth}    \setlength{\logowidth}{70mm}
\newlength{\logopad}      \setlength{\logopad}{17.5mm}
\newlength{\marginleft}   \setlength{\marginleft}{3cm}   % Minimum margins are 2cm
\newlength{\marginright}  \setlength{\marginright}{3cm} 
\newlength{\margintop}    \setlength{\margintop}{3cm}
\newlength{\marginbottom} \setlength{\marginbottom}{3cm}  
\newlength{\marginhead} \setlength{\marginhead}{1cm}
\newlength{\marginfoot} \setlength{\marginfoot}{0.8cm}

\geometry{a4paper, top=\margintop, left=\marginleft, right=\marginright, bottom=\marginbottom, headsep=\marginhead, footskip=\marginfoot, nomarginpar}

\setlength{\parskip}{2ex plus 0.5ex minus 0.2ex}

%% Title page
\makeatletter
\def\degree#1{\gdef\@degree{#1}}
\def\course#1{\gdef\@course{#1}}
\def\subtitle#1{\gdef\@subtitle{#1}}
\def\cid#1{\gdef\@cid{#1}}
\def\supervisor#1{\gdef\@supervisor{#1}}
\def\secondmarker#1{\gdef\@secondmarker{#1}}
\def\submityear#1{\gdef\@submityear{#1}}
\def\extendeddegree#1{\gdef\@extendeddegree{#1}}
\def\thesis#1{\gdef\@thesis{#1}}

\newcommand{\titletext}{\@thesis\ submitted in fulfillment of requirements for the degree of\ \linebreak \textbf{\@extendeddegree\ in \@course}}

\newcommand{\thesisspacing}{
\ifthenelse{\boolean{double_spacing}}{\doublespacing}{\singlespacing}
}

\def\maketitle{

\ifthenelse{\equal{\@degree}{MSc}}
 {
   \setboolean{MEngBEng}{false}
   \extendeddegree{Master of Science}
   \thesis{A Thesis}
 }{
   \setboolean{MEngBEng}{true}
   \ifthenelse{\equal{\@degree}{MEng}}
    {
     \extendeddegree{Master of Engineering}
    }{
     \extendeddegree{Bachelor of Engineering}
    }
    \ifthenelse{\boolean{final_thesis}}
     {
      \thesis{A Thesis}
     }{
      \thesis{A report}
     }
 }

  \begin{titlepage}
    \hypertarget{TitlePage}{}
    \bookmark[dest=TitlePage,level=-1]{Front matter}
	\phantomsection \pdfbookmark[section]{Title page}{title}
    \pgfdeclareimage[width=\logowidth]{IC_New_Logo}{IC_New_Logo}
    \pgftext[at=\pgfpoint{-\marginleft+\logopad}{\margintop+\parskip-\logopad}, top, left]{\pgfuseimage{IC_New_Logo}}

    \begin{center}
	  \vspace*{\fill}
    \vskip 2cm
      \doublespacing {\huge  \textsc \@title} \par\singlespacing
      \vskip 0.5cm
      {\Large \textsc \@subtitle}
      \vskip 2cm
      Authors\\[2mm]
      {\large \textsc \@author}\\[1mm]
      \vskip 1cm

      Supervised by\\[2mm]
      {\large \textsc \@supervisor}\\[1mm]
      \ifthenelse{\boolean{MEngBEng}}{
      \vskip 0.3cm
      
      % --- ROUNDED IMAGE & LEGEND START ---
      \begin{center}
          \begin{tikzpicture}
              \clip[rounded corners=15pt] (-0.28\textwidth, -2cm) rectangle (0.28\textwidth, 2cm);
              \node at (0,0) {\includegraphics[width=0.56\textwidth]{imgs/scaffold_front.jpg}};
          \end{tikzpicture}\\[0.3cm]
          {\small\textit{Scaffold scene, accelerated on FPGA, infinite depth.}}
      \end{center}
      \vskip 0.5cm
      % --- ROUNDED IMAGE & LEGEND END ---
      
      }{\vskip 3.5cm}
      \titletext
	  \vskip 0.5cm
	  Department of Electrical and Electronic Engineering\\
   Imperial College London\\
   \@submityear
      \vspace*{\fill}
    \end{center}
  \end{titlepage}
  
  \pagenumbering{arabic}
  \setcounter{page}{2} 
}
\makeatother

\RequirePackage{silence}
\WarningsOff[everypage]
\RequirePackage[contents={},opacity=1,scale=1,color=black]{background}
\WarningsOn[everypage]

% --- SAFE GLOBAL MACRO PATCHES OUTSIDE OF PREAMBLE BLOCK ---
\RequirePackage{xpatch}
\makeatletter
\xpatchcmd{\chapter}{\thispagestyle{plain}}
                    {\thispagestyle{empty}\stepcounter{counter}}
                    {}{}

% Tighten spacing defaults across native Toc entries globally and safely
\patchcmd{\l@chapter}{\addvspace{#1}}{\addvspace{0.8ex}}{}{}
\renewcommand{\@tocrmarg}{2.5em}
\makeatother
% -----------------------------------------------------------

\RequirePackage{tikzpagenodes}
\RequirePackage{totcount}

\regtotcounter{counter}
\newcounter{counter}

\usetikzlibrary{calc}
\usetikzlibrary{shapes.symbols} 
\usetikzlibrary{shapes.misc} 

\RequirePackage{fancyhdr}

%New brand ImperialBlue
\definecolor{ImperialBlue}{RGB}{0,0,205}

\setlength{\headheight}{21pt}
\fancypagestyle{fancy}{
\fancyhead{}
\fancyfoot{}
\fancyhead[RE]{\color{ImperialBlue}\leftmark}
\fancyhead[LE]{\color{ImperialBlue}\thepage}
\fancyhead[RO]{\color{ImperialBlue}\thepage}
\fancyhead[LO]{\color{ImperialBlue}\rightmark}
\renewcommand{\headrulewidth}{0.5pt}
\renewcommand{\headrule}{\hbox to\headwidth{%
  \color{ImperialBlue}\leaders\hrule height \headrulewidth\hfill}}
\renewcommand{\footrulewidth}{0pt}
}
\fancypagestyle{plain}{%
  \fancyhf{}%
  \fancyhead[LE]{\color{ImperialBlue}\thepage}
  \fancyhead[RO]{\color{ImperialBlue}\thepage}
\renewcommand{\headrulewidth}{0.5pt}
\renewcommand{\headrule}{\hbox to\headwidth{%
  \color{ImperialBlue}\leaders\hrule height \headrulewidth\hfill}}
\renewcommand{\footrulewidth}{0pt}
  \Materialfalse
  \afterpage{\Materialtrue}%
}
\fancypagestyle{empty}{%
  \fancyhf{}%
  \renewcommand{\headrulewidth}{0.0pt}%
  \Materialfalse
  \afterpage{\Materialtrue}%
}

\newif\ifMaterial
\newlength\LabelSize
\setlength\LabelSize{1.5cm}

\AtBeginDocument{%
  \setlength\LabelSize{\dimexpr\textheight/\totvalue{counter}\relax}%
  \ifdim\LabelSize>1.5cm\relax
  \global\setlength\LabelSize{1.5cm}%
  \fi
}
\makeatletter
\newcommand\AddLabels{%
  \Materialtrue
  \AddEverypageHook{%
    \ifMaterial
    \ifodd\value{page}%
    \backgroundsetup{
      angle=0,
      position={current page.east|-current page text area.north east},
      vshift=0pt-(\thecounter-2)*45pt,
      hshift=-15,
      contents={%
        \tikz\node[cho label] {\thechapter};
      }%
    }%
    \else
    \backgroundsetup{
      angle=0,
      position={current page.west|-current page text area.north west},
      vshift=0pt-(\thecounter-2)*45pt,
      hshift=15,
      contents={%
        \tikz\node[che label] {\thechapter};
      }%
    }%
    \fi
    \BgMaterial
    \else\relax\fi
  }%
}
\makeatother
\tikzset{
  che label/.style={fill,rounded rectangle, fill=ImperialBlue,anchor=west,text width=\LabelSize, align=right,text height=30pt,text depth=15pt,text=white,font=\sffamily\fontsize{25pt}{0pt}\selectfont},
}
\tikzset{
  cho label/.style={fill,rounded rectangle, fill=ImperialBlue,anchor=west,text width=\LabelSize, align=left,text height=30pt,text depth=15pt,text=white,font=\sffamily\fontsize{25pt}{0pt}\selectfont},
}

\newcommand\RemoveLabels{\Materialfalse}

\RequirePackage{titlesec}
\titleformat{\chapter}[display]
  {\normalfont\fontsize{90}{92}\raggedleft\bfseries\color{ImperialBlue}}{\ \thechapter}{-50pt}{\Huge\raggedleft\color{ImperialBlue}}
\titlespacing*{\chapter}{0pt}{0pt}{20pt}

\def\preamble{

\dominitoc % Do not change - required
\maketitle % Do not change - required

\pagestyle{empty} % Do not change - required
\frontmatter % Do not change - required
\thesisspacing % Do not change - required

\pagestyle{empty} 

\phantomsection
\addcontentsline{toc}{chapter}{Abstract}\mtcaddchapter 
\chapter*{Abstract}
\addtocounter{counter}{-1}
\input{Abstract.tex} % Do not remove

% --- CLEAN BREAK AFTER ABSTRACT ---
\clearpage 

% --- MERGED ACKNOWLEDGMENTS & DECLARATION OF ORIGINALITY ---
\ifthenelse{\boolean{acknowledgement}}{
\phantomsection
\addcontentsline{toc}{chapter}{Acknowledgments}\mtcaddchapter 

\vspace{0.5cm} 

{\normalfont\Huge\bfseries\raggedleft\color{ImperialBlue} Acknowledgments \par}
\vspace{0.6cm}

We would like to give a special thanks to all those that provided particularly useful assistance, technical or otherwise, throughout our project:\\[0.5cm]

\noindent
\begin{tabularx}{\textwidth}{>{\bfseries}l X}
Ed Stott     & Senior Teaching Fellow \\
Inigo Quilez & Mathematician, developed hundreds of Signed Distance Function GLSL code from which we learned \\
Claude Code  & AI, for immense help in understanding the technique of Ray Marching and its hardware considerations \\
Codex & AI, for immense help in understanding the technique of Ray Marching and its' hardware considerations \\
\end{tabularx}
}{}

\vspace{1.5cm} 
\phantomsection
\addcontentsline{toc}{chapter}{Declaration of Originality}\mtcaddchapter 

{\normalfont\Huge\bfseries\raggedleft\color{ImperialBlue} Declaration of Originality \par}
\vspace{0.6cm}

We hereby declare that the work presented in this report is our own unless otherwise stated. To the best of our knowledge the work is original and ideas developed in collaboration with others have been appropriately referenced.
\vspace{0.6cm}
\begin{figure}[htbp]
    \centering
    % Left Image - Top Aligned
    \begin{minipage}[t]{0.48\textwidth}
        \centering
        \includegraphics[width=\textwidth]{imgs/sphere_sdf_infinite.jpg}
        \label{fig:image1}
    \end{minipage}
    \hfill
    % Right Image - Top Aligned
    \begin{minipage}[t]{0.48\textwidth}
        \centering
        \includegraphics[width=\textwidth]{imgs/sphere_sdf_infinite2.jpg}
    \end{minipage}
    \caption{\textit{Sphere signed distance function, infinite depth, cell size 10, cyclical RGB color palette, 27 frames per second.}}
\end{figure}

\clearpage
\singlespacing % Do not change - required

\setcounter{tocdepth}{1}

% --- HIGHLY CONDENSED TOC CONTAINER BLOCK ---
\begin{spacing}{0.84}
\tableofcontents % Do not change - required
\end{spacing}
\vspace{2cm}
\begin{figure}[h!]
    \centering
    \includegraphics[width=0.8\textwidth]{imgs/initial_mandelbox.jpg}
    \caption{Initial mandelbox tests, looking at the mandelbox. Crashing as we enter the box- march iteration count too high, severe frame rate drop. 25 - 3 frames per second.}
    \label{fig:your_label}
\end{figure}

% --- EMBEDDED REPOSITORY BLOCK AT THE BOTTOM OF TOC PAGE 2 ---
\vspace{\fill} % Pushes the block to the absolute bottom margin of page 2
\noindent
\begin{minipage}{\textwidth}
    \phantomsection
    \addcontentsline{toc}{section}{Source Code Repository}
    \hrule height 0.5pt
    \vspace{0.4cm}
    {\centering\bfseries\large Source Code Repository\par}
    \vspace{0.2cm}
    {\noindent\small The planning, research, hardware design files, software drivers, simulation testbenches, and synthesis scripts mapping out this architecture are fully accessible via GitHub at: \url{https://github.com/thapala2301/SummerProjectMathsAccelerator}
\end{minipage}
% -------------------------------------------------------------

\clearpage

\ifthenelse{\boolean{acronyms}}{
\phantomsection
\addcontentsline{toc}{chapter}{List of Acronyms}\mtcaddchapter 
\chapter*{List of Acronyms}
\addtocounter{counter}{-1}
\input{chapters/ListAcronyms.tex} % OPTIONAL CAN BE REMOVED
}{}

\ifthenelse{\boolean{list_of_figures}}{
\phantomsection
\addcontentsline{toc}{chapter}{\listfigurename}\mtcaddchapter
\listoffigures % Optional
\addtocounter{counter}{-1}
}{}

\ifthenelse{\boolean{list_of_tables}}{
\phantomsection
\addcontentsline{toc}{chapter}
{\listtablename}\mtcaddchapter
\listoftables
\addtocounter{counter}{-1}
}{} 

\mainmatter % Do not change - required
\bookmarksetup{startatroot}
\pagestyle{fancy} % Do not change - required
\ifthenelse{\boolean{edge_labels}}{
\AddLabels % Do not change - required
}{}
}

\ifthenelse{\boolean{acronyms}}{
\phantomsection
\addcontentsline{toc}{chapter}{List of Acronyms}\mtcaddchapter 
\chapter*{List of Acronyms}
\addtocounter{counter}{-1}
\input{chapters/ListAcronyms.tex} % OPTIONAL CAN BE REMOVED
}{}

\ifthenelse{\boolean{list_of_figures}}{
\phantomsection
\addcontentsline{toc}{chapter}{\listfigurename}\mtcaddchapter
\listoffigures % Optional
\addtocounter{counter}{-1}
}{}

\ifthenelse{\boolean{list_of_tables}}{
\phantomsection
\addcontentsline{toc}{chapter}
{\listtablename}\mtcaddchapter
\listoftables
\addtocounter{counter}{-1}
}{} 

\mainmatter % Do not change - required
\bookmarksetup{startatroot}
\pagestyle{fancy} % Do not change - required
\ifthenelse{\boolean{edge_labels}}{
\AddLabels % Do not change - required
}{}
}

\newcommand{\conclusions}[1]{
\cleardoublepage % Do not change - required
\RemoveLabels % Do not change - required
\cleardoublepage\phantomsection
\addcontentsline{toc}{chapter}{{#1}}\mtcaddchapter 
\chapter*{{#1}}
\markboth{{\MakeUppercase {#1}}}{{\MakeUppercase {#1}}}
\addtocounter{counter}{-1}
% Edit the content of these files 
\input{Conclusions} % Do not remove
\cleardoublepage % Do not change - required
\ifthenelse{\boolean{edge_labels}}{
\AddLabels % Do not change - required
}{}
}
PAPER := main
LATEXMK := latexmk

.PHONY: all clean distclean watch

all: $(PAPER).pdf

$(PAPER).pdf: $(PAPER).tex references.bib
	$(LATEXMK) -pdf -interaction=nonstopmode -halt-on-error $(PAPER).tex

watch:
	$(LATEXMK) -pdf -pvc -interaction=nonstopmode $(PAPER).tex

clean:
	$(LATEXMK) -c
	rm -f *.bbl *.run.xml

distclean:
	$(LATEXMK) -C
	rm -f *.bbl *.run.xml

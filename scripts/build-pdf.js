const { readFileSync, writeFileSync } = require('fs');
const { join } = require('path');

async function buildPDF() {
  const mdPath = join(__dirname, '..', 'docs', 'Zixir Language complete guide.md');
  const pdfPath = join(__dirname, '..', 'docs', 'Zixir Language complete guide.pdf');
  
  const md = readFileSync(mdPath, 'utf-8');
  
  const { mdToPdf } = require('md-to-pdf');
  
  const pdf = await mdToPdf(
    { content: md },
    {
      launch_options: { args: ['--no-sandbox', '--disable-setuid-sandbox'] },
      pdf_options: {
        format: 'A4',
        margin: { top: '25mm', right: '20mm', bottom: '25mm', left: '20mm' },
        printBackground: true,
      },
      stylesheet: [],
      css: `
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; font-size: 14px; line-height: 1.6; color: #333; }
        h1 { color: #1a1a2e; border-bottom: 2px solid #6c63ff; padding-bottom: 10px; }
        h2 { color: #16213e; border-bottom: 1px solid #ddd; padding-bottom: 5px; margin-top: 30px; }
        h3 { color: #0f3460; }
        code { background: #f4f4f4; padding: 2px 6px; border-radius: 3px; font-size: 13px; }
        pre { background: #1a1a2e; color: #e0e0e0; padding: 16px; border-radius: 8px; overflow-x: auto; }
        pre code { background: none; color: inherit; padding: 0; }
        table { border-collapse: collapse; width: 100%; margin: 16px 0; }
        th, td { border: 1px solid #ddd; padding: 8px 12px; text-align: left; }
        th { background: #6c63ff; color: white; }
        tr:nth-child(even) { background: #f9f9f9; }
        blockquote { border-left: 4px solid #6c63ff; margin: 16px 0; padding: 8px 16px; background: #f8f8ff; }
      `,
    }
  );

  if (pdf) {
    writeFileSync(pdfPath, pdf.content);
    console.log('PDF generated: ' + pdfPath);
  }
}

buildPDF().catch(err => {
  console.error('PDF generation failed:', err.message);
  process.exit(1);
});

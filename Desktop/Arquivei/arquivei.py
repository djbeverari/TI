from flask import Flask, request, redirect, url_for, render_template, flash
import os
import shutil

app = Flask(__name__)
app.secret_key = "supersecretkey"
UPLOAD_FOLDER = 'uploads'
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER

def extrair_cnpj(nome_arquivo):
    if len(nome_arquivo) < 21:
        return None
    cnpj = nome_arquivo[6:20]
    return cnpj

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/upload', methods=['POST'])
def upload_file():
    if 'files[]' not in request.files:
        flash('No file part')
        return redirect(request.url)
    files = request.files.getlist('files[]')
    for file in files:
        if file.filename == '':
            flash('No selected file')
            continue
        if file:
            filename = file.filename
            file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
            file.save(file_path)
            cnpj = extrair_cnpj(filename)
            if cnpj:
                destino = os.path.join(app.config['UPLOAD_FOLDER'], cnpj)
                if not os.path.exists(destino):
                    os.makedirs(destino)
                shutil.move(file_path, os.path.join(destino, filename))
                flash(f"Arquivo '{filename}' movido para a pasta '{destino}'")
            else:
                flash(f"Não foi possível extrair o CNPJ do arquivo '{filename}'")
    return redirect(url_for('index'))

if __name__ == '__main__':
    if not os.path.exists(UPLOAD_FOLDER):
        os.makedirs(UPLOAD_FOLDER)
    app.run(debug=True, port=5002)

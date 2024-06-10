from flask import Flask, request, redirect, url_for, render_template, flash, session
import os
import shutil
import time

app = Flask(__name__)
app.secret_key = "supersecretkey"
UPLOAD_FOLDER = 'uploads'
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER

def extrair_cnpj(nome_arquivo):
    if len(nome_arquivo) < 21:
        return None
    cnpj = nome_arquivo[6:20]
    return cnpj

def extrair_mes(nome_arquivo):
    if len(nome_arquivo) < 6:
        return None
    mes = nome_arquivo[4:6]
    return mes

@app.route('/')
def index():
    message = session.pop('message', None)
    return render_template('index.html', message=message)

@app.route('/upload', methods=['POST'])
def upload_file():
    if 'files[]' not in request.files:
        flash('No file part')
        return redirect(request.url)
    files = request.files.getlist('files[]')
    total_moved_files = 0
    for file in files:
        if file.filename == '':
            flash('No selected file')
            continue
        if file:
            filename = file.filename
            file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
            file.save(file_path)
            cnpj = extrair_cnpj(filename)
            mes = extrair_mes(filename)
            if cnpj and mes:
                destino = os.path.join(app.config['UPLOAD_FOLDER'], cnpj, mes)
                if not os.path.exists(destino):
                    os.makedirs(destino)
                shutil.move(file_path, os.path.join(destino, filename))
                total_moved_files += 1
            else:
                flash(f"Não foi possível extrair o CNPJ ou o mês do arquivo '{filename}'")
    # Define a mensagem com o total de arquivos movidos
    session['message'] = f"{total_moved_files} arquivo(s) movido(s) para a pasta 'Uploads'"
    # Adiciona um pequeno atraso antes de redirecionar para garantir que a mensagem seja exibida
    time.sleep(0.5)
    return redirect(url_for('index'))

if __name__ == '__main__':
    if not os.path.exists(UPLOAD_FOLDER):
        os.makedirs(UPLOAD_FOLDER)
    # Mude o host para '0.0.0.0' para escutar em todas as interfaces de rede
    app.run(debug=True, host='0.0.0.0', port=5002)


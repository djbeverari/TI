import pandas as pd
from flask import Flask, request, render_template
import os
import xlwt
import re

app = Flask(__name__)

# Função para processar o arquivo TXT e converter em DataFrame
def read_txt_to_dataframe(txt_file):
    records = []
    with open(txt_file, 'r', encoding='latin1') as file:
        next(file)  # Ignorando a primeira linha que é apenas cabeçalho
        for line1, line2 in zip(file, file):  # Lendo duas linhas de cada vez
            cpf_match = re.search(r'^(\d{11})', line1)
            if cpf_match:
                cpf = cpf_match.group(1).strip()
            else:
                cpf = ''
                
            nome_match = re.search(r'^\d{11}(.{49})', line1)
            if nome_match:
                nome = nome_match.group(1).strip()
                nome = re.sub(r'\d', '', nome)  # Removendo dígitos do CPF do campo do nome
            else:
                nome = ''
                
            email_match = re.search(r'(.{66})(.{50})', line1)
            if email_match:
                email = email_match.group(2).strip()
            else:
                email = ''
                
            cep_endereco_match = re.search(r'(.{150})(.{110})', line1)
            if cep_endereco_match:
                cep_endereco = cep_endereco_match.group(2).strip()
                cep = cep_endereco[:8].strip()
                logradouro = cep_endereco[8:].strip()
            else:
                cep = ''
                logradouro = ''
                
            numero_complemento_match = re.search(r'(.{260})(.{30})', line2)
            if numero_complemento_match:
                numero_complemento = numero_complemento_match.group(1).strip()
                numero = numero_complemento[:7].strip()
                complemento = numero_complemento[7:].strip()
            else:
                numero = ''
                complemento = ''
                
            bairro_match = re.search(r'(.{290})(.{30})', line2)
            if bairro_match:
                bairro = bairro_match.group(2).strip()
            else:
                bairro = ''
                
            cidade_match = re.search(r'(.{320})(.{30})', line2)
            if cidade_match:
                cidade = cidade_match.group(2).strip()
            else:
                cidade = ''
                
            uf_match = re.search(r'(.{350})(.{2})$', line2)
            if uf_match:
                uf = uf_match.group(2).strip()
            else:
                uf = ''

            record = {
                'Nome': nome,
                'Email': email,
                'CPF/CNPJ': cpf,
                'CEP': cep,
                'Logradouro': logradouro,
                'Número': numero,
                'Complemento': complemento,
                'Bairro': bairro,
                'Cidade': cidade,
                'UF': uf
            }
            records.append(record)

    df = pd.DataFrame(records)
    if df.empty:
        print("O DataFrame está vazio. Verifique o conteúdo do arquivo TXT.")
    return df

# Função para salvar o DataFrame em um arquivo XLS
def save_to_excel(dataframe, xls_file):
    xls_file = xls_file + '.xls'
    workbook = xlwt.Workbook()
    sheet = workbook.add_sheet('Sheet1')

    # Escrever cabeçalho
    headers = ['Nome', 'Email', 'CPF/CNPJ', 'CEP', 'Logradouro', 'Número', 'Complemento', 'Bairro', 'Cidade', 'UF']
    for col, header in enumerate(headers):
        sheet.write(0, col, header)

    # Escrever dados
    for row, (_, data) in enumerate(dataframe.iterrows(), start=1):
        sheet.write(row, 0, data['Nome'])
        sheet.write(row, 1, data['Email'])
        sheet.write(row, 2, data['CPF/CNPJ'])
        sheet.write(row, 3, data['CEP'])
        sheet.write(row, 4, data['Logradouro'])
        sheet.write(row, 5, data['Número'])
        sheet.write(row, 6, data['Complemento'])
        sheet.write(row, 7, data['Bairro'])
        sheet.write(row, 8, data['Cidade'])
        sheet.write(row, 9, data['UF'])

    workbook.save(xls_file)
    print("Arquivo salvo com sucesso como", xls_file)

# Rota para a página inicial
@app.route('/')
def index():
    return render_template('index.html')

# Rota para lidar com o upload do arquivo TXT
@app.route('/upload', methods=['POST'])
def upload():
    if 'file' not in request.files:
        return 'Nenhum arquivo enviado'
    file = request.files['file']
    if file.filename == '':
        return 'Nome de arquivo inválido'
    if not os.path.exists('uploads'):
        os.makedirs('uploads')
    txt_filename = file.filename
    txt_file_path = os.path.join('uploads', txt_filename)
    file.save(txt_file_path)
    print(f"Arquivo {txt_filename} salvo em {txt_file_path}")
    
    # Processar o arquivo TXT e criar o DataFrame
    try:
        df = read_txt_to_dataframe(txt_file_path)
        if df.empty:
            return "O DataFrame está vazio. Verifique o conteúdo do arquivo TXT."
        print(df.head())
    except Exception as e:
        print(f"Erro ao processar o arquivo TXT: {e}")
        return f"Erro ao processar o arquivo TXT: {e}"
    
    # Salvar o DataFrame no arquivo XLS
    try:
        xls_file = os.path.join('uploads', 'dados_salvos')
        save_to_excel(df, xls_file)
        print(f"Arquivo XLS salvo em {xls_file}")
    except Exception as e:
        print(f"Erro ao salvar o arquivo XLS: {e}")
        return f"Erro ao salvar o arquivo XLS: {e}"
    
    return "Arquivo processado com sucesso."

if __name__ == "__main__":
    app.run(debug=True, port=5001)

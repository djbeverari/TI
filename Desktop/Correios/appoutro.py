import pandas as pd
from flask import Flask, request, render_template
import os
import xlwt

app = Flask(__name__)

# Função para processar o arquivo TXT e converter em DataFrame
def read_txt_to_dataframe(txt_file):
    records = []
    with open(txt_file, 'r', encoding='latin1') as file:
        for line in file:
            line = line.strip().split()
            if len(line) < 10:
                print(f"Ignorando linha incompleta ou mal formatada: {line}")
                continue  # Ignorar linhas incompletas ou mal formatadas
            cpf = line[0]
            email_index = None
            for i, word in enumerate(line):
                if '@' in word:
                    email_index = i
                    break
            if email_index is None or email_index < 1 or email_index + 9 >= len(line):
                print(f"Ignorando linha sem e-mail válido: {line}")
                continue  # Ignorar linhas sem e-mail válido ou com e-mail na primeira posição
            nome = ' '.join(line[1:email_index])[:30]  # Limite de 30 caracteres para o nome
            email = line[email_index]
            cep = line[email_index + 1]
            logradouro = ' '.join(line[email_index + 2:email_index + 4])
            numero = line[email_index + 4]
            complemento = ' '.join(line[email_index + 5:email_index + 7])
            bairro = line[email_index + 7]
            cidade = line[email_index + 8]
            estado = line[email_index + 9]
            
            record = {
                'CPF': cpf,
                'Nome': nome,
                'Email': email,
                'CEP': cep,
                'Logradouro': logradouro,
                'Número': numero,
                'Complemento': complemento,
                'Bairro': bairro,
                'Cidade': cidade,
                'Estado': estado
            }
            records.append(record)

    df = pd.DataFrame(records)
    return df

# Função para salvar o DataFrame em um arquivo XLS
def save_to_excel(dataframe, xls_file):
    xls_file = xls_file + '.xls'
    workbook = xlwt.Workbook()
    sheet = workbook.add_sheet('Sheet1')

    # Escrever cabeçalho
    headers = ['CPF', 'Nome', 'Email', 'CEP', 'Logradouro', 'Número', 'Complemento', 'Bairro', 'Cidade', 'Estado']
    for col, header in enumerate(headers):
        sheet.write(0, col, header)

    # Escrever dados
    for row, (_, data) in enumerate(dataframe.iterrows(), start=1):
        sheet.write(row, 0, str(data['CPF']))
        sheet.write(row, 1, data['Nome'])
        sheet.write(row, 2, data['Email'])
        sheet.write(row, 3, str(data['CEP']))
        sheet.write(row, 4, data['Logradouro'])
        sheet.write(row, 5, str(data['Número']))
        sheet.write(row, 6, data['Complemento'])
        sheet.write(row, 7, data['Bairro'])
        sheet.write(row, 8, data['Cidade'])
        sheet.write(row, 9, data['Estado'])

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
    
    return f"Arquivo {txt_filename} enviado e convertido para XLS com sucesso!"

if __name__ == '__main__':
    app.run(debug=True, port=5001)

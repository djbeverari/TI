from flask import Flask, request, render_template, send_file
import os
import xlwt

app = Flask(__name__)

# Diretório para salvar os arquivos enviados
UPLOAD_FOLDER = 'uploads'
if not os.path.exists(UPLOAD_FOLDER):
    os.makedirs(UPLOAD_FOLDER)

# Diretório para salvar o arquivo XLS de saída
OUTPUT_FOLDER = 'output'
if not os.path.exists(OUTPUT_FOLDER):
    os.makedirs(OUTPUT_FOLDER)

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/upload', methods=['POST'])
def upload_file():
    # Obtém o arquivo enviado pelo usuário
    file = request.files['file']
    
    # Salva o arquivo no diretório de uploads
    file_path = os.path.join(UPLOAD_FOLDER, file.filename)
    file.save(file_path)
    
    # Lê o conteúdo do arquivo TXT
    with open(file_path, 'r') as f:
        content = f.readlines()

    # Ignorar a primeira linha (cabeçalho)
    content = content[1:]         
    
    # Cria uma lista de dicionários com os dados
    data = []
    for line in content:
        # Obtenha o CPF da linha
        cpf = line[:12].strip()
        
        # Remova apenas o primeiro "2" do CPF, se presente
        cpf = cpf.replace("2", "", 1)
        
        nome = line[12:50].strip()
        email = line[50:95].strip()
        telefone = line[427:438].strip()
        celular = line [427:438].strip()
        cep = line[215:223].strip()
        logradouro = line[223:273].strip()
        numero = line[273:279].strip()
        complemento = line[279:309].strip()
        bairro = line[309:334].strip()
        cidade = line[334:384].strip()
        uf = line[384:386].strip()
        data_row = {
            'CPF': cpf,
            'Nome': nome,
            'Email': email,
            'CEP': cep,
            'Logradouro': logradouro,
            'Número': numero,
            'Complemento': complemento,
            'Bairro': bairro,
            'Cidade': cidade,
            'Telefone': telefone,
            'Celular' : celular
        }
        data.append(data_row)
    
    # Cria um novo arquivo Excel de saída no formato .xls
    output_file = os.path.join(os.getcwd(), OUTPUT_FOLDER, 'dados_salvos.xls')
    output_workbook = xlwt.Workbook()
    output_sheet = output_workbook.add_sheet('Sheet1')
    
    try:
        # Escreve o cabeçalho no arquivo de saída
        headers = ['Nome', 'Email', 'CPF', 'Telefone', 'Celular', 'CEP', 'Logradouro', 'Número', 'Complemento', 'Bairro', 'Cidade']
        for col, header in enumerate(headers):
            output_sheet.write(0, col, header)
        
        # Adiciona os dados ao arquivo de saída
        for row, data_row in enumerate(data[:-1], start=1):
            output_sheet.write(row, 0, data_row['Nome'])
            output_sheet.write(row, 1, data_row['Email'])
            output_sheet.write(row, 2, data_row['CPF'])
            output_sheet.write(row, 3, data_row['Telefone'])
            output_sheet.write(row, 4, data_row['Celular'])
            output_sheet.write(row, 5, data_row['CEP'])
            output_sheet.write(row, 6, data_row['Logradouro'])
            output_sheet.write(row, 7, data_row['Número'])
            output_sheet.write(row, 8, data_row['Complemento'])
            output_sheet.write(row, 9, data_row['Bairro'])
            output_sheet.write(row, 10, data_row['Cidade'])
        
        # Salva o arquivo Excel de saída
        output_workbook.save(output_file)
        
        # Retorna o arquivo XLS para download
        return send_file(output_file, as_attachment=True)
    except Exception as e:
        return f"Erro: {e}"

if __name__ == '__main__':
    app.run(debug=True, port=5001)

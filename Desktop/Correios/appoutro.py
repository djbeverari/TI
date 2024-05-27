from flask import Flask, request, render_template, send_file
import os
import xlrd
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
    
    # Cria uma lista de dicionários com os dados
    data = []
    for line in content:
        fields = line.split()
        if len(fields) >= 10:
            data.append({
                'Código': fields[0].strip(),
                'Nome Completo': ' '.join(fields[1:-9]).strip(),
                'Email': fields[-9].strip(),
                'CEP': fields[-8].strip(),
                'Endereço': ' '.join(fields[-7:-4]).strip(),
                'Número': fields[-4].strip(),
                'Complemento': fields[-3].strip(),
                'Bairro': fields[-2].strip(),
                'Cidade': fields[-1].strip(),
                'Telefone': fields[-5].strip()
            })
    
    # Abre o arquivo Excel de template no formato .xls
    template_file = 'dados.xls'
    template_workbook = xlrd.open_workbook(template_file)
    template_sheet = template_workbook.sheet_by_index(0)
    
    # Cria um novo arquivo Excel de saída no formato .xls
    output_file = os.path.join(os.getcwd(), OUTPUT_FOLDER, 'dados_salvos.xls')
    output_workbook = xlwt.Workbook()
    output_sheet = output_workbook.add_sheet('Sheet1')
    
    try:
        # Copia os dados do template para o arquivo de saída
        for row in range(template_sheet.nrows):
            for col in range(template_sheet.ncols):
                output_sheet.write(row, col, template_sheet.cell_value(row, col))
        
        # Adiciona os dados ao arquivo de saída
        for row, data_row in enumerate(data):
            output_sheet.write(row + template_sheet.nrows, 0, data_row['Código'])
            output_sheet.write(row + template_sheet.nrows, 1, data_row['Nome Completo'])
            output_sheet.write(row + template_sheet.nrows, 2, data_row['Email'])
            output_sheet.write(row + template_sheet.nrows, 3, data_row['CEP'])
            output_sheet.write(row + template_sheet.nrows, 4, data_row['Endereço'])
            output_sheet.write(row + template_sheet.nrows, 5, data_row['Número'])
            output_sheet.write(row + template_sheet.nrows, 6, data_row['Complemento'])
            output_sheet.write(row + template_sheet.nrows, 7, data_row['Bairro'])
            output_sheet.write(row + template_sheet.nrows, 8, data_row['Cidade'])
            output_sheet.write(row + template_sheet.nrows, 9, data_row['Telefone'])
        
        # Salva o arquivo Excel de saída
        output_workbook.save(output_file)
        
        # Retorna o arquivo XLS para download
        return send_file(output_file, as_attachment=True)
    except FileNotFoundError:
        return "Erro: O arquivo de template 'dados.xls' não foi encontrado."

if __name__ == '__main__':
    app.run(debug=True, port=5001)